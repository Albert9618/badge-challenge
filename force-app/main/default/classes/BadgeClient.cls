/**
 * Sends certification status updates to the external badging platform.
 * The endpoint comes from the Badge_Settings__mdt "Default" record.
 *
 * Throws BadgeSyncException on any failure so the caller can record it. A failed
 * update must never be swallowed: that is how the original bug stayed invisible.
 */
public with sharing class BadgeClient {

    public class BadgeSyncException extends Exception {}

    // Kept low so a full batch chunk stays inside the 120s cumulative callout limit per transaction.
    @TestVisible private static final Integer TIMEOUT_MS = 5000;

    public static void syncStatus(Certification__c cert) {
        Badge_Settings__mdt settings = Badge_Settings__mdt.getInstance('Default');
        if (settings == null || String.isBlank(settings.Endpoint__c)) {
            throw new BadgeSyncException('Badge_Settings__mdt "Default" has no Endpoint__c configured.');
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(settings.Endpoint__c);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(TIMEOUT_MS);
        req.setBody(JSON.serialize(new Map<String, Object>{
            'badge_id' => cert.BadgeId__c,
            'status' => 'expired',
            'expires_at' => String.valueOf(cert.ExpirationDate__c)
        }));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() >= 300) {
            throw new BadgeSyncException('HTTP ' + res.getStatusCode() + ' for badge ' + cert.BadgeId__c
                + ': ' + res.getBody());
        }
    }
}
