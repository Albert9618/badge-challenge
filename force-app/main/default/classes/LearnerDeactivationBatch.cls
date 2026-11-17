/**
 * Runs nightly after learners are deactivated. Expires each deactivated learner's active
 * certifications, then hands the badge updates to BadgeSyncBatch.
 *
 * This job only does DML. Callouts are not allowed after DML in the same transaction, so badge
 * updates run in their own job. Certifications that need a badge update are marked
 * BadgeSyncStatus__c = 'Pending' in the same DML that expires them, so the second job finds its
 * work by query and no state is passed between jobs.
 *
 * Run it with: Database.executeBatch(new LearnerDeactivationBatch());
 */
public with sharing class LearnerDeactivationBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Tests can't chain batches from finish(), so they switch this off and call finish() directly
    // to check the handoff. Production always chains.
    @TestVisible private Boolean chainBadgeSync = true;

    private Integer expired = 0;
    private Integer failed = 0;
    private List<String> sampleErrors = new List<String>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // No LIMIT: a QueryLocator streams up to 50 million rows through execute().
        return Database.getQueryLocator([
            SELECT Id, BadgeId__c
            FROM Certification__c
            WHERE Status__c = 'Active' AND User__r.IsActive = false
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Certification__c> scope) {
        Date today = Date.today();
        for (Certification__c cert : scope) {
            cert.Status__c = 'Expired';
            cert.ExpirationDate__c = today;
            if (String.isNotBlank(cert.BadgeId__c)) {
                cert.BadgeSyncStatus__c = 'Pending';
                cert.BadgeSyncError__c = null;
            }
        }

        // Partial success: one bad row must not roll back the other 199.
        List<Database.SaveResult> results = Database.update(scope, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                expired++;
            } else {
                failed++;
                if (sampleErrors.size() < 10) {
                    sampleErrors.add('Certification ' + scope[i].Id + ': ' + results[i].getErrors()[0].getMessage());
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        BatchAlertService.alertIfFailed('LearnerDeactivationBatch', bc.getJobId(), expired, failed, sampleErrors);

        // Always chain, even after failures: the certifications that did expire still need their badges.
        if (chainBadgeSync) {
            Database.executeBatch(new BadgeSyncBatch(), BadgeSyncBatch.SCOPE_SIZE);
        }
    }
}
