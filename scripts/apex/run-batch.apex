Id jobId = Database.executeBatch(new LearnerDeactivationBatch());
System.debug('Started LearnerDeactivationBatch: ' + jobId);
