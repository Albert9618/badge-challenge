/**
 * Shared test data and callout mock. Builds the same shape as the seed scripts:
 * 60 deactivated learners x 3 certifications (2 with badges) = 180 certs / 120 badges,
 * plus one active learner (the running user) whose certification must stay Active.
 */
@IsTest
public class BadgeTestData {

    public static final Integer LEARNER_COUNT = 60;
    public static final Integer LEARNER_CERTS = 180;
    public static final Integer LEARNER_BADGES = 120;

    public static void createSeedData() {
        Profile standardUser = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        List<User> learners = new List<User>();
        for (Integer i = 0; i < LEARNER_COUNT; i++) {
            learners.add(new User(
                Alias = 'tl' + i,
                Email = 'test.learner' + i + '@badge-challenge.example',
                EmailEncodingKey = 'UTF-8',
                LastName = 'Learner ' + i,
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = standardUser.Id,
                TimeZoneSidKey = 'America/Denver',
                Username = 'test.learner' + i + '.' + UserInfo.getOrganizationId() + '@badge-challenge.example',
                IsActive = false
            ));
        }
        // Users are setup objects, so insert them in their own context to avoid mixed DML.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert learners;
        }

        Date expires = Date.today().addMonths(6);
        List<Certification__c> certs = new List<Certification__c>();
        for (User learner : learners) {
            certs.add(new Certification__c(Name = 'SAFe Agilist', User__c = learner.Id, Status__c = 'Active',
                ExpirationDate__c = expires, BadgeId__c = 'agilist-' + learner.Alias));
            certs.add(new Certification__c(Name = 'SAFe Scrum Master', User__c = learner.Id, Status__c = 'Active',
                ExpirationDate__c = expires, BadgeId__c = 'ssm-' + learner.Alias));
            certs.add(new Certification__c(Name = 'AI-Native Ready', User__c = learner.Id, Status__c = 'Active',
                ExpirationDate__c = expires));
        }
        certs.add(new Certification__c(Name = 'SAFe Agilist', User__c = UserInfo.getUserId(), Status__c = 'Active',
            ExpirationDate__c = expires, BadgeId__c = 'agilist-admin'));
        insert certs;
    }

    /** Puts the data in the state LearnerDeactivationBatch leaves it in, without running it. */
    public static void markLearnerCertsExpiredAndPending() {
        List<Certification__c> certs = [
            SELECT Id, BadgeId__c FROM Certification__c WHERE User__r.IsActive = false
        ];
        for (Certification__c cert : certs) {
            cert.Status__c = 'Expired';
            cert.ExpirationDate__c = Date.today();
            if (cert.BadgeId__c != null) {
                cert.BadgeSyncStatus__c = 'Pending';
            }
        }
        update certs;
    }

    /**
     * Drives one BadgeSyncBatch.execute() chunk directly. A test can only run one chunk per transaction:
     * a second chunk's callouts would follow the first chunk's DML and fail. In production every
     * chunk is its own transaction, so that cannot happen.
     */
    public static void runOneChunk(BadgeSyncBatch batch, List<Certification__c> work) {
        Assert.isTrue(work.size() <= BadgeSyncBatch.SCOPE_SIZE, 'A test transaction can run one chunk only');
        batch.execute(null, work);
    }

    /** Marks all but `keep` pending badges as already Synced, so one real executeBatch chunk covers the rest. */
    public static void leaveOnlyPending(Integer keep) {
        List<Certification__c> pending = [SELECT Id FROM Certification__c WHERE BadgeSyncStatus__c = 'Pending'];
        List<Certification__c> done = new List<Certification__c>();
        for (Integer i = keep; i < pending.size(); i++) {
            done.add(new Certification__c(Id = pending[i].Id, BadgeSyncStatus__c = 'Synced'));
        }
        update done;
    }

    public class StubContext implements Database.BatchableContext {
        public Id getJobId() { return null; }
        public Id getChildJobId() { return null; }
    }

    /** Stands in for the badging platform. Counts calls and keeps request bodies. */
    public class BadgeCalloutMock implements HttpCalloutMock {
        public Integer statusCode;
        public Integer calls = 0;
        public List<String> requestBodies = new List<String>();

        public BadgeCalloutMock(Integer statusCode) {
            this.statusCode = statusCode;
        }

        public HttpResponse respond(HttpRequest req) {
            calls++;
            requestBodies.add(req.getBody());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(statusCode < 300 ? '{"ok":true}' : '{"error":"simulated failure"}');
            return res;
        }
    }
}
