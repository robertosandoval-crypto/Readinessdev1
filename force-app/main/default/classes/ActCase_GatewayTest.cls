@isTest
private class ActCase_GatewayTest {

  @TestSetup
  static void setup() {
    Learning_Rubric__c parentRubric = new Learning_Rubric__c(
      Name = 'Parent Template Rubric'
    );
    insert parentRubric;

    Learner_Profile__c lp = new Learner_Profile__c(
      User__c = UserInfo.getUserId(),
      Status__c = 'Active'
    );
    insert lp;

    Learning_Rubric__c lr = new Learning_Rubric__c(
      Learner_Profile__c = lp.Id,
      Parent_Rubric__c = parentRubric.Id,
      Name = 'Case Test Rubric'
    );
    insert lr;

    // Create the Tier 1 Support queue in a separate context to avoid MIXED_DML
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Group q = new Group(
        Name = 'Tier 1 Support',
        Type = 'Queue'
      );
      insert q;

      QueueSobject qs = new QueueSobject(
        QueueId = q.Id,
        SobjectType = 'Case'
      );
      insert qs;
    }
  }

  @isTest
  static void testSuccessfulCaseCreation() {
    Learning_Rubric__c lr = [SELECT Id FROM Learning_Rubric__c WHERE Learner_Profile__c != null LIMIT 1];

    ActCase_Gateway.Request req = new ActCase_Gateway.Request();
    req.caseDescription = 'I am having trouble with my assessment.';
    req.caseSubject = 'Assessment Issue';
    req.varLearningRubricId = lr.Id;

    Test.startTest();
    List<ActGateway_Responses.GatewayResponse> responses =
      ActCase_Gateway.execute(new List<ActCase_Gateway.Request>{ req });
    Test.stopTest();

    System.assertEquals(1, responses.size());
    Map<String, Object> envelope = (Map<String, Object>) System.JSON.deserializeUntyped(responses[0].responseJson);
    System.assertEquals(true, envelope.get('ok'), 'Should be a success response');

    List<Object> dataList = (List<Object>) envelope.get('data');
    System.assert(!dataList.isEmpty(), 'Data should contain the created case');
    Map<String, Object> caseData = (Map<String, Object>) dataList[0];
    System.assertNotEquals(null, caseData.get('CaseNumber'), 'CaseNumber should be present');
    System.assert(((String) caseData.get('Subject')).contains('Assessment Issue'), 'Subject should contain input');
    System.assert(((String) caseData.get('Subject')).contains('Case Test Rubric'), 'Subject should contain rubric name');

    // Verify case was actually created
    List<Case> cases = [SELECT Id, Subject, Description FROM Case WHERE Subject LIKE '%Assessment Issue%'];
    System.assertEquals(1, cases.size(), 'One case should have been created');
  }

  @isTest
  static void testNoLearnerProfile() {
    Learning_Rubric__c lr = [SELECT Id FROM Learning_Rubric__c WHERE Learner_Profile__c != null LIMIT 1];

    // Delete profile to simulate missing profile
    delete [SELECT Id FROM Learner_Profile__c];

    ActCase_Gateway.Request req = new ActCase_Gateway.Request();
    req.caseDescription = 'Test description';
    req.caseSubject = 'Test subject';
    req.varLearningRubricId = lr.Id;

    Test.startTest();
    List<ActGateway_Responses.GatewayResponse> responses =
      ActCase_Gateway.execute(new List<ActCase_Gateway.Request>{ req });
    Test.stopTest();

    Map<String, Object> envelope = (Map<String, Object>) System.JSON.deserializeUntyped(responses[0].responseJson);
    System.assertEquals(false, envelope.get('ok'), 'Should be an error response');
    System.assert(((String) envelope.get('error')).contains('No active Learner Profile'));
  }

  @isTest
  static void testDefaultUserId() {
    Learning_Rubric__c lr = [SELECT Id FROM Learning_Rubric__c WHERE Learner_Profile__c != null LIMIT 1];

    ActCase_Gateway.Request req = new ActCase_Gateway.Request();
    req.caseDescription = 'Default user test';
    req.caseSubject = 'Default User';
    req.varLearningRubricId = lr.Id;
    // userId left blank — should default to running user

    Test.startTest();
    List<ActGateway_Responses.GatewayResponse> responses =
      ActCase_Gateway.execute(new List<ActCase_Gateway.Request>{ req });
    Test.stopTest();

    Map<String, Object> envelope = (Map<String, Object>) System.JSON.deserializeUntyped(responses[0].responseJson);
    System.assertEquals(true, envelope.get('ok'), 'Should succeed with default userId');
  }
}
