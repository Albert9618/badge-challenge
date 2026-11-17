// Creates 60 deactivated learners. They are inserted inactive, so they don't use any licenses.
Profile standardUser = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
String orgId = UserInfo.getOrganizationId();

List<User> learners = new List<User>();
for (Integer i = 0; i < 60; i++) {
    learners.add(new User(
        Alias = 'lrn' + i,
        Email = 'learner' + i + '@badge-challenge.example',
        EmailEncodingKey = 'UTF-8',
        FirstName = 'Learner',
        LastName = String.valueOf(i),
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_US',
        ProfileId = standardUser.Id,
        TimeZoneSidKey = 'America/Denver',
        Username = 'learner' + i + '.' + orgId + '@badge-challenge.example',
        IsActive = false
    ));
}
insert learners;
System.debug('Inserted ' + learners.size() + ' deactivated learners');
