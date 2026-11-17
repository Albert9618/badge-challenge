@IsTest
private class BadgeSyncBatchTest {

    // A test transaction can run exactly one chunk, so keep one full chunk's worth of badges pending.
    private static final Integer ONE_CHUNK = BadgeSyncBatch.SCOPE_SIZE;

    @TestSetup
    static void setup() {
        BadgeTestData.createSeedData();
        BadgeTestData.markLearnerCertsExpiredAndPending();
    }

    private static Integer countBySyncStatus(String status) {
        return [SELECT COUNT() FROM Certification__c WHERE BadgeSyncStatus__c = :status];
    }

    // R2: the start query finds the whole seed set. (The platform feeds it to execute() 20 at a time;
    // a test can run only one chunk, so the multi-chunk run is verified in the org.)
    @IsTest
    static void startQueryFindsEverySeedBadge() {
        List<Certification__c> work = Database.query(BadgeSyncBatch.PENDING_QUERY);
        Assert.areEqual(BadgeTestData.LEARNER_BADGES, work.size(), 'All 120 badges are found, none without a badge');
        Assert.areEqual(BadgeTestData.LEARNER_BADGES / BadgeSyncBatch.SCOPE_SIZE, 6, 'Seed data is six chunks of work');
    }

    @IsTest
    static void realBatchRunSyncsOneFullChunkAndSendsTheExpectedPayload() {
        BadgeTestData.leaveOnlyPending(ONE_CHUNK);
        BadgeTestData.BadgeCalloutMock mock = new BadgeTestData.BadgeCalloutMock(200);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new BadgeSyncBatch(), BadgeSyncBatch.SCOPE_SIZE);
        Test.stopTest();

        Assert.areEqual(BadgeTestData.LEARNER_BADGES, countBySyncStatus('Synced'), 'The chunk joins the already synced badges');
        Assert.areEqual(0, countBySyncStatus('Pending'), 'Nothing is left pending');
        Assert.areEqual(ONE_CHUNK, mock.calls, 'Only the pending badges were sent, not the already synced ones');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.requestBodies[0]);
        Assert.areEqual('expired', body.get('status'), 'Status sent to the platform is expired');
        Assert.areEqual(String.valueOf(Date.today()), body.get('expires_at'), 'Expiry date is sent');
        Assert.isNotNull(body.get('badge_id'), 'Badge id is sent');
    }

    // The original bug hid failures in a debug log. Here a failure lands on the record and in an email.
    @IsTest
    static void failedCalloutsAreRecordedAndAlerted() {
        BadgeTestData.leaveOnlyPending(ONE_CHUNK);
        Test.setMock(HttpCalloutMock.class, new BadgeTestData.BadgeCalloutMock(500));

        Test.startTest();
        List<Certification__c> work = Database.query(BadgeSyncBatch.PENDING_QUERY);
        BadgeSyncBatch batch = new BadgeSyncBatch();
        BadgeTestData.runOneChunk(batch, work);
        batch.finish(new BadgeTestData.StubContext());
        Integer emails = Limits.getEmailInvocations(); // read before stopTest(), which resets Limits
        Test.stopTest();

        Assert.areEqual(1, emails, 'finish() emails an alert for the failures');
        Assert.areEqual(ONE_CHUNK, countBySyncStatus('Failed'), 'Every failed badge is flagged Failed');
        Assert.areEqual(BadgeTestData.LEARNER_BADGES - ONE_CHUNK, countBySyncStatus('Synced'),
            'The others are untouched');
        Certification__c failed = [
            SELECT BadgeSyncError__c FROM Certification__c WHERE BadgeSyncStatus__c = 'Failed' LIMIT 1
        ];
        Assert.isTrue(failed.BadgeSyncError__c.contains('HTTP 500'), 'The reason is stored on the record');
    }

    @IsTest
    static void aCleanRunSendsNoAlert() {
        BadgeTestData.leaveOnlyPending(ONE_CHUNK);
        Test.setMock(HttpCalloutMock.class, new BadgeTestData.BadgeCalloutMock(200));

        Test.startTest();
        List<Certification__c> work = Database.query(BadgeSyncBatch.PENDING_QUERY);
        BadgeSyncBatch batch = new BadgeSyncBatch();
        BadgeTestData.runOneChunk(batch, work);
        batch.finish(new BadgeTestData.StubContext());
        Integer emails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(0, countBySyncStatus('Failed'), 'Precondition: the run really succeeded');
        Assert.areEqual(0, emails, 'No email when everything succeeded');
    }

    @IsTest
    static void failedBadgesAreRetriedOnTheNextRun() {
        BadgeTestData.leaveOnlyPending(ONE_CHUNK);
        Test.setMock(HttpCalloutMock.class, new BadgeTestData.BadgeCalloutMock(500));
        Test.startTest();
        Database.executeBatch(new BadgeSyncBatch(), BadgeSyncBatch.SCOPE_SIZE);
        Test.stopTest();
        Assert.areEqual(ONE_CHUNK, countBySyncStatus('Failed'), 'Precondition: they failed');

        // The badging platform recovers; the next run's query picks the failures up again.
        BadgeTestData.BadgeCalloutMock recovered = new BadgeTestData.BadgeCalloutMock(200);
        Test.setMock(HttpCalloutMock.class, recovered);
        List<Certification__c> work = Database.query(BadgeSyncBatch.PENDING_QUERY);
        Assert.areEqual(ONE_CHUNK, work.size(), 'Failed badges are picked up again');
        BadgeTestData.runOneChunk(new BadgeSyncBatch(), work);

        Assert.areEqual(BadgeTestData.LEARNER_BADGES, countBySyncStatus('Synced'), 'Retry syncs them');
        Assert.areEqual(0,
            [SELECT COUNT() FROM Certification__c WHERE BadgeSyncError__c != null],
            'The old error is cleared on success');
    }

    @IsTest
    static void aFullChunkStaysUnderTheCalloutLimit() {
        // The default batch size of 200 would blow the 100-callouts-per-transaction limit with 120 badges.
        Assert.isTrue(BadgeSyncBatch.SCOPE_SIZE < 100, 'Scope must stay under the per-transaction callout limit');
    }
}
