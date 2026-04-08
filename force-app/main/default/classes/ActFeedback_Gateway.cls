/**
 * @description Invocable handler for retrieving a learner's latest feedback.
 * Queries the Learning Rubric's Latest_Feedback__c field and converts it from
 * JSON to human-readable text using the ACT_Latest_Feedback_Json_to_text prompt template.
 *
 * Replaces Flow: ACT_Get_Learner_Feedback
 * Planner action: ACT_Get_Learner_latest_Feedback1
 */
public with sharing class ActFeedback_Gateway {

  private static final String ACTION_NAME = 'GetLearnerLatestFeedback';

  public class Request {
    @InvocableVariable(
      label='User ID'
      description='The Salesforce User Id of the logged-in learner. Used to look up the active Learner Profile. Defaults to the running user if left blank.'
      required=false
    )
    public String userId;

    @InvocableVariable(
      label='Record ID'
      description='The Learning_Rubric__c record Id from the current page context. Used to retrieve the Latest_Feedback__c field for conversion to human-readable text.'
      required=true
    )
    public String varRecordId;
  }

  @InvocableMethod(
    label='Get Learner Latest Feedback'
    description='Retrieves the latest feedback from the Learning Rubric record and converts it from JSON to human-readable text using the ACT_Latest_Feedback_Json_to_text prompt template.'
  )
  public static List<ActGateway_Responses.GatewayResponse> execute(List<Request> requests) {
    List<ActGateway_Responses.GatewayResponse> responses = new List<ActGateway_Responses.GatewayResponse>();
    for (Request req : requests) {
      responses.add(handleRequest(req));
    }
    return responses;
  }

  private static ActGateway_Responses.GatewayResponse handleRequest(Request req) {
    try {
      // Resolve userId
      String resolvedUserId = String.isBlank(req.userId) ? UserInfo.getUserId() : req.userId;

      // Get active Learner Profile
      List<SObject> profiles = [
        SELECT Id FROM Learner_Profile__c
        WHERE User__c = :resolvedUserId AND Status__c = 'Active'
        LIMIT 1
      ];
      if (profiles.isEmpty()) {
        return buildEmptyFeedbackResponse('No active Learner Profile found.');
      }

      // Get Learning Rubric with Latest_Feedback__c
      List<SObject> rubrics = [
        SELECT Id, Latest_Feedback__c FROM Learning_Rubric__c
        WHERE Id = :req.varRecordId AND Learner_Profile__c = :profiles[0].Id
        LIMIT 1
      ];
      if (rubrics.isEmpty()) {
        return buildEmptyFeedbackResponse('No Learning Rubric found for the given record.');
      }

      String rawFeedback = (String) rubrics[0].get('Latest_Feedback__c');
      if (String.isBlank(rawFeedback)) {
        return buildEmptyFeedbackResponse('No feedback recorded on this Learning Rubric yet.');
      }

      // Convert JSON feedback to readable text via prompt template
      String readableFeedback = convertFeedbackToText(rawFeedback);

      Map<String, Object> data = new Map<String, Object>{
        'latestFeedback' => readableFeedback
      };
      Map<String, Object> envelope = AgentCore_Response.buildSuccess(
        ACTION_NAME,
        new List<Map<String, Object>>{ data },
        null
      );
      envelope.put(AgentCore_Response.FIELD_SUMMARY, 'Latest feedback retrieved and converted to text.');
      return new ActGateway_Responses.GatewayResponse(envelope);

    } catch (Exception e) {
      return ActGateway_Responses.fromError(
        ACTION_NAME,
        'Failed to retrieve feedback: ' + e.getMessage(),
        new List<String>{ 'Verify the Learning Rubric exists and has feedback recorded.' }
      );
    }
  }

  private static String convertFeedbackToText(String rawFeedbackJson) {
    if (AgentCore_Response.isApexTestContext()) {
      return 'Test feedback content';
    }
    try {
      ConnectApi.EinsteinPromptTemplateGenerationsInput ptInput =
        new ConnectApi.EinsteinPromptTemplateGenerationsInput();
      ptInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
      ptInput.additionalConfig.applicationName = 'ActFeedback_Gateway';
      ptInput.isPreview = false;

      Map<String, ConnectApi.WrappedValue> inputParams =
        new Map<String, ConnectApi.WrappedValue>();
      ConnectApi.WrappedValue feedbackVal = new ConnectApi.WrappedValue();
      feedbackVal.value = rawFeedbackJson;
      inputParams.put('Input:latestFeedback', feedbackVal);
      ptInput.inputParams = inputParams;

      ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
        ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
          'ACT_Latest_Feedback_Json_to_text', ptInput
        );
      if (result != null && result.generations != null && !result.generations.isEmpty()) {
        return result.generations[0].text;
      }
    } catch (Exception e) {
      // Fall back to raw JSON if prompt template fails
      return rawFeedbackJson;
    }
    return rawFeedbackJson;
  }

  private static ActGateway_Responses.GatewayResponse buildEmptyFeedbackResponse(String reason) {
    Map<String, Object> data = new Map<String, Object>{
      'latestFeedback' => ''
    };
    Map<String, Object> envelope = AgentCore_Response.buildSuccess(
      ACTION_NAME,
      new List<Map<String, Object>>{ data },
      null
    );
    envelope.put(AgentCore_Response.FIELD_SUMMARY, reason);
    return new ActGateway_Responses.GatewayResponse(envelope);
  }
}
