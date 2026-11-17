/**
 * Emails someone when a batch run had failures, so nobody has to read debug logs (R3).
 * Recipient: Badge_Settings__mdt.Default.Alert_Email__c, else the user who started the job.
 */
public with sharing class BatchAlertService {

    private static final Integer MAX_SAMPLE_ERRORS = 10;

    /**
     * @param jobName      shown in the subject, e.g. 'BadgeSyncBatch'
     * @param jobId        the AsyncApexJob Id (may be null); used to pick up chunk-level failures
     *                     such as an uncaught exception that rolled a whole chunk back
     * @param processed    records the job handled successfully
     * @param failed       records the job caught and recorded as failed
     * @param sampleErrors the first few error messages collected during the run
     * @return true when an alert was sent
     */
    public static Boolean alertIfFailed(String jobName, Id jobId, Integer processed, Integer failed,
                                        List<String> sampleErrors) {
        Integer chunkErrors = 0;
        String chunkStatus = null;
        if (jobId != null) {
            for (AsyncApexJob job : [SELECT NumberOfErrors, ExtendedStatus FROM AsyncApexJob WHERE Id = :jobId]) {
                chunkErrors = job.NumberOfErrors;
                chunkStatus = job.ExtendedStatus;
            }
        }
        if (failed == 0 && chunkErrors == 0) {
            return false;
        }

        Messaging.SingleEmailMessage mail = buildMessage(jobName, jobId, processed, failed, chunkErrors,
            chunkStatus, sampleErrors);
        List<Messaging.SendEmailResult> results = Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ mail }, false);
        if (!results[0].isSuccess()) {
            // Last resort: the alert itself failed. The Failed flag on the records is still queryable.
            System.debug(LoggingLevel.ERROR, 'Could not send batch alert: ' + results[0].getErrors());
        }
        return true;
    }

    @TestVisible
    private static Messaging.SingleEmailMessage buildMessage(String jobName, Id jobId, Integer processed,
            Integer failed, Integer chunkErrors, String chunkStatus, List<String> sampleErrors) {
        List<String> lines = new List<String>{
            jobName + ' finished with problems.',
            '',
            'Job Id: ' + jobId,
            'Succeeded: ' + processed,
            'Failed (recorded on the records): ' + failed,
            'Chunks that failed outright (rolled back): ' + chunkErrors
        };
        if (String.isNotBlank(chunkStatus)) {
            lines.add('Job status detail: ' + chunkStatus);
        }
        if (sampleErrors != null && !sampleErrors.isEmpty()) {
            lines.add('');
            lines.add('First errors:');
            Integer shown = Math.min(sampleErrors.size(), MAX_SAMPLE_ERRORS);
            for (Integer i = 0; i < shown; i++) {
                lines.add(' - ' + sampleErrors[i]);
            }
        }
        lines.add('');
        lines.add('Failed badge updates are retried automatically on the next run.');

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ recipient() });
        mail.setSubject('[Badge sync] ' + jobName + ' needs attention');
        mail.setPlainTextBody(String.join(lines, '\n'));
        mail.setSaveAsActivity(false);
        return mail;
    }

    @TestVisible
    private static String recipient() {
        Badge_Settings__mdt settings = Badge_Settings__mdt.getInstance('Default');
        if (settings != null && String.isNotBlank(settings.Alert_Email__c)) {
            return settings.Alert_Email__c;
        }
        return UserInfo.getUserEmail();
    }
}
