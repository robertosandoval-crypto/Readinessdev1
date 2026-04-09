/**
 * @description Invocable handler for retrieving a learner's latest feedback.
 * Queries the Learning Rubric's Latest_Feedback__c field and returns the raw
 * JSON directly — the planner agent formats it for display and downstream
 * actions (ActQA_Gateway) reason over source truth instead of an LLM rewrite.
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
      description='The Learning_Rubric__c record Id from the current page context. Used to retrieve the Latest_Feedback__c field.'
      required=true
    )
    public String varRecordId;
  }

  @InvocableMethod(
    label='Get Learner Latest Feedback'
    description='Retrieves the latest feedback JSON from the Learning Rubric record. Returns the raw structured feedback so the agent can format it for display and downstream actions reason over source truth.'
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

      // Return the raw JSON directly — no LLM middleware rewrite.
      // The planner agent formats for display; ActQA_Gateway reasons over source truth.
      Map<String, Object> data = new Map<String, Object>{
        'latestFeedback' => rawFeedback
      };
      Map<String, Object> envelope = AgentCore_Response.buildSuccess(
        ACTION_NAME,
        new List<Map<String, Object>>{ data },
        null
      );
      envelope.put(AgentCore_Response.FIELD_SUMMARY, 'Latest feedback retrieved as structured JSON.');
      return new ActGateway_Responses.GatewayResponse(envelope);

    } catch (Exception e) {
      return ActGateway_Responses.fromError(
        ACTION_NAME,
        'Failed to retrieve feedback: ' + e.getMessage(),
        new List<String>{ 'Verify the Learning Rubric exists and has feedback recorded.' }
      );
    }
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
