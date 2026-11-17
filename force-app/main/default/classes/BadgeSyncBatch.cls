/**
 * Tells the badging platform that expired certifications' badges are expired.
 *
 * Finds its own work: certifications that are Expired, have a badge, and are Pending (or Failed
 * from an earlier run, so an outage on the badging side heals itself on the next run).
 *
 * Each execute() makes all its callouts first and writes results in a single DML at the end.
 * Callouts are never made after DML in the same transaction.
 */
public with sharing class BadgeSyncBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    // 20 callouts x 5s timeout = 100s worst case, inside the 120s cumulative callout limit,
    // and far below the 100-callouts-per-transaction limit.
    public static final Integer SCOPE_SIZE = 20;

    private Integer synced = 0;
    private Integer failed = 0;
    private List<String> sampleErrors = new List<String>();

    @TestVisible private static final String PENDING_QUERY =
        'SELECT Id, BadgeId__c, ExpirationDate__c FROM Certification__c '
        + 'WHERE Status__c = \'Expired\' AND BadgeId__c != null AND BadgeSyncStatus__c IN (\'Pending\', \'Failed\')';

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(PENDING_QUERY);
    }

    public void execute(Database.BatchableContext bc, List<Certification__c> scope) {
        List<Certification__c> results = new List<Certification__c>();

        // 1. Callouts only.
        for (Certification__c cert : scope) {
            Certification__c result = new Certification__c(Id = cert.Id);
            try {
                BadgeClient.syncStatus(cert);
                result.BadgeSyncStatus__c = 'Synced';
                result.BadgeSyncError__c = null;
                synced++;
            } catch (Exception e) {
                result.BadgeSyncStatus__c = 'Failed';
                result.BadgeSyncError__c = e.getMessage().left(255);
                failed++;
                if (sampleErrors.size() < 10) {
                    sampleErrors.add(cert.BadgeId__c + ': ' + e.getMessage().left(200));
                }
            }
            results.add(result);
        }

        // 2. One DML at the end to record what happened.
        Database.update(results, false);
    }

    public void finish(Database.BatchableContext bc) {
        BatchAlertService.alertIfFailed('BadgeSyncBatch', bc.getJobId(), synced, failed, sampleErrors);
    }
}
