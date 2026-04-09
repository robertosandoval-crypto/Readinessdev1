@isTest
private class ActFeedback_GatewayTest {

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
      Name = 'Feedback Test Rubric',
      Latest_Feedback__c = '{"score": 7, "comments": "Good job on rapport building."}'
    );
    insert lr;
  }

  @isTest
  static void testSuccessWithFeedback() {
    Learning_Rubric__c lr = [SELECT Id FROM Learning_Rubric__c WHERE Learner_Profile__c != null LIMIT 1];

    ActFeedback_Gateway.Request req = new ActFeedback_Gateway.Request();
    req.varRecordId = lr.Id;

    Test.startTest();
    List<ActGateway_Responses.GatewayResponse> responses =
      ActFeedback_Gateway.execute(new List<ActFeedback_Gateway.Request>{ req });
    Test.stopTest();

    System.assertEquals(1, responses.size());
    Map<String, Object> envelope = (Map<String, Object>) System.JSON.deserializeUntyped(responses[0].responseJson);
    System.assertEquals(true, envelope.get('ok'), 'Should be a success response');

    List<Object> dataList = (List<Object>) envelope.get('data');
    Map<String, Object> data = (Map<String, Object>) dataList[0];
    // In test context, convertFeedbackToText returns 'Test feedback content'
    System.assertEquals('Test feedback content', data.get('latestFeedback'));
  }

  @isTest
  static void testNoLearnerProfile() {
    Learning_Rubric__c lr = [SELECT Id FROM Learning_Rubric__c WHERE Learner_Profile__c != null LIMIT 1];

    // Delete the learner profile to simulate no profile
    delete [SELECT Id FROM Learner_Profile__c];

    ActFeedback_Gateway.Request req = new ActFeedback_Gateway.Request();
    req.varRecordId = lr.Id;

    Test.startTest();
    List<ActGateway_Responses.GatewayResponse> responses =
      ActFeedback_Gateway.execute(new List<ActFeedback_Gateway.Request>{ req });
    Test.stopTest();

    Map<String, Object> envelope = (Map<String, Object>) System.JSON.deserializeUntyped(responses[0].responseJson);
    // buildEmptyFeedbackResponse still returns ok=true with empty latestFeedback
    System.assertEquals(true, envelope.get('ok'));
    List<Object> dataList = (List<Object>) envelope.get('data');
    Map<String, Object> data = (Map<String, Object>) dataList[0];
    System.assertEquals('', data.get('latestFeedback'));
  }

  @isTest
  static void testNoFeedbackOnRubric() {
    Learner_Profile__c lp = [SELECT Id FROM Learner_Profile__c LIMIT 1];

    // Create rubric with no feedback
    Learning_Rubric__c parentRubric = [SELECT Id FROM Learning_Rubric__c WHERE Learner_Profile__c = null LIMIT 1];
    Learning_Rubric__c lr2 = new Learning_Rubric__c(
      Learner_Profile__c = lp.Id,
      Parent_Rubric__c = parentRubric.Id,
      Name = 'Empty Feedback Rubric'
    );
    insert lr2;

    ActFeedback_Gateway.Request req = new ActFeedback_Gateway.Request();
    req.varRecordId = lr2.Id;

    Test.startTest();
    List<ActGateway_Responses.GatewayResponse> responses =
      ActFeedback_Gateway.execute(new List<ActFeedback_Gateway.Request>{ req });
    Test.stopTest();

    Map<String, Object> envelope = (Map<String, Object>) System.JSON.deserializeUntyped(responses[0].responseJson);
    System.assertEquals(true, envelope.get('ok'));
    List<Object> dataList = (List<Object>) envelope.get('data');
    Map<String, Object> data = (Map<String, Object>) dataList[0];
    System.assertEquals('', data.get('latestFeedback'));
  }

  @isTest
  static void testWrongRecordId() {
    ActFeedback_Gateway.Request req = new ActFeedback_Gateway.Request();
    req.varRecordId = 'a00000000000000AAA'; // fake Id

    Test.startTest();
    List<ActGateway_Responses.GatewayResponse> responses =
      ActFeedback_Gateway.execute(new List<ActFeedback_Gateway.Request>{ req });
    Test.stopTest();

    Map<String, Object> envelope = (Map<String, Object>) System.JSON.deserializeUntyped(responses[0].responseJson);
    // No matching rubric → empty feedback response
    System.assertEquals(true, envelope.get('ok'));
  }
}
