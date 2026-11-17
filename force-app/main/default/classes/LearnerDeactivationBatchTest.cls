@IsTest
private class LearnerDeactivationBatchTest {

    @TestSetup
    static void setup() {
        BadgeTestData.createSeedData();
    }

    private static Integer jobErrors(String className) {
        Integer errors = 0;
        for (AsyncApexJob job : [
            SELECT NumberOfErrors FROM AsyncApexJob WHERE ApexClass.Name = :className AND JobType = 'BatchApex'
        ]) {
            errors += job.NumberOfErrors;
        }
        return errors;
    }

    // The original bug: the job reported Completed while every chunk had failed and rolled back.
    // That is why this asserts on the job's own error count, not just on the data.
    @IsTest
    static void expiresAllDeactivatedLearnersCertsInOneRunWithoutJobErrors() {
        BadgeTestData.BadgeCalloutMock mock = new BadgeTestData.BadgeCalloutMock(200);
        Test.setMock(HttpCalloutMock.class, mock);

        LearnerDeactivationBatch batch = new LearnerDeactivationBatch();
        batch.chainBadgeSync = false; // a test can't chain from finish(); the handoff has its own test
        Test.startTest();
        Database.executeBatch(batch); // default scope of 200 holds all 180 certs
        Test.stopTest();

        Assert.areEqual(0, jobErrors('LearnerDeactivationBatch'), 'No chunk of the expiry job may fail');

        List<Certification__c> expired = [
            SELECT ExpirationDate__c FROM Certification__c WHERE Status__c = 'Expired' AND User__r.IsActive = false
        ];
        Assert.areEqual(BadgeTestData.LEARNER_CERTS, expired.size(), 'All 180 deactivated learners\' certs expire in one run');
        for (Certification__c cert : expired) {
            Assert.areEqual(Date.today(), cert.ExpirationDate__c, 'Expiration date is set to today');
        }
        Assert.areEqual(0,
            [SELECT COUNT() FROM Certification__c WHERE Status__c = 'Active' AND User__r.IsActive = false],
            'No deactivated learner keeps an active certification');
        Assert.areEqual(0, mock.calls, 'Expiring certifications makes no callouts, so DML can never precede one');
    }

    @IsTest
    static void activeLearnersCertificationStaysActive() {
        LearnerDeactivationBatch batch = new LearnerDeactivationBatch();
        batch.chainBadgeSync = false;
        Test.startTest();
        Database.executeBatch(batch);
        Test.stopTest();

        Certification__c adminCert = [
            SELECT Status__c, BadgeSyncStatus__c FROM Certification__c WHERE User__c = :UserInfo.getUserId()
        ];
        Assert.areEqual('Active', adminCert.Status__c, 'An active learner keeps their certification');
        Assert.isNull(adminCert.BadgeSyncStatus__c, 'No badge update is queued for an active learner');
    }

    @IsTest
    static void onlyCertsWithBadgesAreMarkedForSync() {
        LearnerDeactivationBatch batch = new LearnerDeactivationBatch();
        batch.chainBadgeSync = false;
        Test.startTest();
        Database.executeBatch(batch);
        Test.stopTest();

        Assert.areEqual(BadgeTestData.LEARNER_BADGES,
            [SELECT COUNT() FROM Certification__c WHERE BadgeSyncStatus__c = 'Pending'],
            'Exactly the 120 certs with a badge are Pending');
        Assert.areEqual(0,
            [SELECT COUNT() FROM Certification__c WHERE BadgeId__c = null AND BadgeSyncStatus__c != null],
            'Certs without a badge are never marked for sync');
    }

    // R4: badge updates are their own asynchronous process.
    @IsTest
    static void finishHandsBadgeUpdatesToASeparateJob() {
        Test.setMock(HttpCalloutMock.class, new BadgeTestData.BadgeCalloutMock(200));

        new LearnerDeactivationBatch().finish(new BadgeTestData.StubContext());

        Assert.areEqual(1,
            [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'BadgeSyncBatch' AND JobType = 'BatchApex'],
            'The expiry job queues a separate BadgeSyncBatch job');
    }

    // R3: someone finds out about a failed run without reading debug logs.
    @IsTest
    static void alertEmailIsSentOnlyWhenSomethingFailed() {
        Boolean cleanRun = BatchAlertService.alertIfFailed('BadgeSyncBatch', null, 120, 0, new List<String>());
        Assert.isFalse(cleanRun, 'A clean run sends no alert');
        Assert.areEqual(0, Limits.getEmailInvocations(), 'No email on a clean run');

        Boolean failedRun = BatchAlertService.alertIfFailed('BadgeSyncBatch', null, 118, 2,
            new List<String>{ 'agilist-tl1: HTTP 500' });
        Assert.isTrue(failedRun, 'A run with failures sends an alert');
        Assert.areEqual(1, Limits.getEmailInvocations(), 'Exactly one alert email');
    }

    @IsTest
    static void alertEmailContainsTheDetailsNeededToAct() {
        Messaging.SingleEmailMessage mail = BatchAlertService.buildMessage('BadgeSyncBatch', null, 118, 2, 0, null,
            new List<String>{ 'agilist-tl1: HTTP 500' });

        Assert.isTrue(mail.getSubject().contains('BadgeSyncBatch'), 'Subject names the job');
        Assert.isTrue(mail.getPlainTextBody().contains('agilist-tl1: HTTP 500'), 'Body carries the error');
        Assert.isTrue(mail.getPlainTextBody().contains('Failed (recorded on the records): 2'), 'Body carries the counts');
        Assert.areEqual(UserInfo.getUserEmail(), mail.getToAddresses()[0], 'Falls back to the running user');
    }
}
