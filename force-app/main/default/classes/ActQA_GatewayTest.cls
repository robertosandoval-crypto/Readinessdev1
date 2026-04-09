@isTest
private class ActQA_GatewayTest {

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
      Name = 'QA Test Rubric',
      Latest_Feedback__c = '{"score": 6, "comments": "Needs improvement on closing."}'
    );
    insert lr;

    Attempt__c att = new Attempt__c(
      Learning_Rubric__c = lr.Id,
      Transcript_Text__c = 'Test transcript for QA testing.'
    );
    insert att;
  }

  @isTest
  static void testSuccessPath() {
    Learning_Rubric__c lr = [SELECT Id FROM Learning_Rubric__c WHERE Learner_Profile__c != null LIMIT 1];

    ActQA_Gateway.Request req = new ActQA_Gateway.Request();
    req.latestFeedback = 'You scored 6/10. Needs improvement on closing.';
    req.learnerQuestion = 'Why did I fail?';
    req.learningrubricId = lr.Id;

    Test.startTest();
    List<ActGateway_Responses.GatewayResponse> responses =
      ActQA_Gateway.execute(new List<ActQA_Gateway.Request>{ req });
    Test.stopTest();

    System.assertEquals(1, responses.size());
    Map<String, Object> envelope = (Map<String, Object>) System.JSON.deserializeUntyped(responses[0].responseJson);
    System.assertEquals(true, envelope.get('ok'), 'Should be a success response');

    List<Object> dataList = (List<Object>) envelope.get('data');
    Map<String, Object> data = (Map<String, Object>) dataList[0];
    // In test context, generateCoachingAnswer returns 'Test coaching answer'
    System.assertEquals('Test coaching answer', data.get('agentAnswer'));
  }

  @isTest
  static void testRubricNotFound() {
    ActQA_Gateway.Request req = new ActQA_Gateway.Request();
    req.latestFeedback = 'Some feedback';
    req.learnerQuestion = 'What is my score?';
    req.learningrubricId = 'a00000000000000AAA'; // fake Id

    Test.startTest();
    List<ActGateway_Responses.GatewayResponse> responses =
      ActQA_Gateway.execute(new List<ActQA_Gateway.Request>{ req });
    Test.stopTest();

    Map<String, Object> envelope = (Map<String, Object>) System.JSON.deserializeUntyped(responses[0].responseJson);
    System.assertEquals(false, envelope.get('ok'), 'Should be an error response');
    System.assert(((String) envelope.get('error')).contains('Learning Rubric not found'));
  }

  @isTest
  static void testNoAttempt() {
    Learner_Profile__c lp = [SELECT Id FROM Learner_Profile__c LIMIT 1];

    // Create a rubric with no attempts
    Learning_Rubric__c parentRubric = [SELECT Id FROM Learning_Rubric__c WHERE Learner_Profile__c = null LIMIT 1];
    Learning_Rubric__c lr2 = new Learning_Rubric__c(
      Learner_Profile__c = lp.Id,
      Parent_Rubric__c = parentRubric.Id,
      Name = 'No Attempt QA Rubric'
    );
    insert lr2;

    ActQA_Gateway.Request req = new ActQA_Gateway.Request();
    req.latestFeedback = 'Some feedback';
    req.learnerQuestion = 'Why did I fail?';
    req.learningrubricId = lr2.Id;

    Test.startTest();
    List<ActGateway_Responses.GatewayResponse> responses =
      ActQA_Gateway.execute(new List<ActQA_Gateway.Request>{ req });
    Test.stopTest();

    Map<String, Object> envelope = (Map<String, Object>) System.JSON.deserializeUntyped(responses[0].responseJson);
    System.assertEquals(true, envelope.get('ok'), 'Should succeed with empty agentAnswer');
    List<Object> dataList = (List<Object>) envelope.get('data');
    Map<String, Object> data = (Map<String, Object>) dataList[0];
    System.assertEquals('', data.get('agentAnswer'));
  }
}
