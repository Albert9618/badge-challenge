// Gives each deactivated learner three active certifications (two with badges),
// and gives the admin user (an active learner) one certification that must stay active.
List<User> learners = [
    SELECT Id, Alias FROM User
    WHERE Email LIKE '%@badge-challenge.example' AND IsActive = false
];
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
System.debug('Inserted ' + certs.size() + ' certifications');
