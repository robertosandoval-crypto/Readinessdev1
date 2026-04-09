@isTest
private class ActInit_GatewayTest {

  @TestSetup
  static void setup() {
    // Create a parent rubric (template — no Learner Profile)
    Learning_Rubric__c parentRubric = new Learning_Rubric__c(
      Name = 'Parent Template Rubric'
    );
    insert parentRubric;

    // Create a Learner Profile for the running user
    Learner_Profile__c lp = new Learner_Profile__c(
      User__c = UserInfo.getUserId(),
      Status__c = 'Active'
    );
    insert lp;

    // Create a Learning Rubric linked to the learner profile
    Learning_Rubric__c lr = new Learning_Rubric__c(
      Learner_Profile__c = lp.Id,
      Parent_Rubric__c = parentRubric.Id,
      Name = 'Test Rubric'
    );
    insert lr;

    // Create an Attempt with a transcript
    Attempt__c att = new Attempt__c(
      Learning_Rubric__c = lr.Id,
      Transcript_Text__c = 'Sample transcript text for testing.'
    );
    insert att;
  }

  @isTest
  static void testSuccessPath() {
    Learning_Rubric__c lr = [SELECT Id FROM Learning_Rubric__c WHERE Learner_Profile__c != null LIMIT 1];

    ActInit_Gateway.Request req = new ActInit_Gateway.Request();
    req.varRecordId = lr.Id;

    Test.startTest();
    List<ActGateway_Responses.GatewayResponse> responses =
      ActInit_Gateway.execute(new List<ActInit_Gateway.Request>{ req });
    Test.stopTest();

    System.assertEquals(1, responses.size(), 'Should return one response');
    String json = responses[0].responseJson;
    System.assertNotEquals(null, json, 'Response JSON should not be null');
    Map<String, Object> envelope = (Map<String, Object>) System.JSON.deserializeUntyped(json);
    System.assertEquals(true, envelope.get('ok'), 'Should be a success response');

    List<Object> dataList = (List<Object>) envelope.get('data');
    System.assert(!dataList.isEmpty(), 'Data should contain session info');
    Map<String, Object> data = (Map<String, Object>) dataList[0];
    System.assertNotEquals(null, data.get('userName'), 'userName should be present');
    System.assertNotEquals(null, data.get('learningRubricName'), 'learningRubricName should be present');
    System.assertNotEquals(null, data.get('learningRubricId'), 'learningRubricId should be present');
  }

  @isTest
  static void testWrongRubric_NoProfile() {
    // Use a fake record ID that won't match any rubric
    ActInit_Gateway.Request req = new ActInit_Gateway.Request();
    req.userId = UserInfo.getUserId();
    req.varRecordId = 'a00000000000000AAA'; // fake Id

    Test.startTest();
    List<ActGateway_Responses.GatewayResponse> responses =
      ActInit_Gateway.execute(new List<ActInit_Gateway.Request>{ req });
    Test.stopTest();

    Map<String, Object> envelope = (Map<String, Object>) System.JSON.deserializeUntyped(responses[0].responseJson);
    System.assertEquals(false, envelope.get('ok'), 'Should be an error response');
    List<Object> dataList = (List<Object>) envelope.get('data');
    System.assert(!dataList.isEmpty(), 'Data should contain error details');
    Map<String, Object> data = (Map<String, Object>) dataList[0];
    System.assertNotEquals(null, data.get('outWrongLearningRubric'), 'Should have wrong rubric error');
  }

  @isTest
  static void testNoAttempt() {
    Learner_Profile__c lp = [SELECT Id FROM Learner_Profile__c LIMIT 1];

    // Create a second rubric with no attempts
    Learning_Rubric__c parentRubric = [SELECT Id FROM Learning_Rubric__c WHERE Learner_Profile__c = null LIMIT 1];
    Learning_Rubric__c lr2 = new Learning_Rubric__c(
      Learner_Profile__c = lp.Id,
      Parent_Rubric__c = parentRubric.Id,
      Name = 'Empty Rubric'
    );
    insert lr2;

    ActInit_Gateway.Request req = new ActInit_Gateway.Request();
    req.varRecordId = lr2.Id;

    Test.startTest();
    List<ActGateway_Responses.GatewayResponse> responses =
      ActInit_Gateway.execute(new List<ActInit_Gateway.Request>{ req });
    Test.stopTest();

    Map<String, Object> envelope = (Map<String, Object>) System.JSON.deserializeUntyped(responses[0].responseJson);
    System.assertEquals(false, envelope.get('ok'), 'Should be an error response');
    List<Object> dataList = (List<Object>) envelope.get('data');
    Map<String, Object> data = (Map<String, Object>) dataList[0];
    System.assertNotEquals(null, data.get('outNoAttemptReasons'), 'Should have no attempt error');
  }

  @isTest
  static void testMissingTranscript() {
    Learner_Profile__c lp = [SELECT Id FROM Learner_Profile__c LIMIT 1];

    // Create rubric + attempt with blank transcript
    Learning_Rubric__c parentRubric = [SELECT Id FROM Learning_Rubric__c WHERE Learner_Profile__c = null LIMIT 1];
    Learning_Rubric__c lr3 = new Learning_Rubric__c(
      Learner_Profile__c = lp.Id,
      Parent_Rubric__c = parentRubric.Id,
      Name = 'No Transcript Rubric'
    );
    insert lr3;

    Attempt__c att = new Attempt__c(
      Learning_Rubric__c = lr3.Id,
      Transcript_Text__c = ''
    );
    insert att;

    ActInit_Gateway.Request req = new ActInit_Gateway.Request();
    req.varRecordId = lr3.Id;

    Test.startTest();
    List<ActGateway_Responses.GatewayResponse> responses =
      ActInit_Gateway.execute(new List<ActInit_Gateway.Request>{ req });
    Test.stopTest();

    Map<String, Object> envelope = (Map<String, Object>) System.JSON.deserializeUntyped(responses[0].responseJson);
    System.assertEquals(false, envelope.get('ok'), 'Should be an error response');
    List<Object> dataList = (List<Object>) envelope.get('data');
    Map<String, Object> data = (Map<String, Object>) dataList[0];
    System.assertNotEquals(null, data.get('outTranscriptMissing'), 'Should have missing transcript error');
  }
}
