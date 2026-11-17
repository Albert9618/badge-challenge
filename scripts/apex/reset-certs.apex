// Puts every certification back to Active so the batch can be run again.
List<Certification__c> certs = [SELECT Id FROM Certification__c];
for (Certification__c cert : certs) {
    cert.Status__c = 'Active';
    cert.ExpirationDate__c = Date.today().addMonths(6);
    cert.BadgeSyncStatus__c = null;
    cert.BadgeSyncError__c = null;
}
update certs;
System.debug('Reset ' + certs.size() + ' certifications');
