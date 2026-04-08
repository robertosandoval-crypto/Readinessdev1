/**
 * @description Invocable handler for generating coaching answers from learner feedback.
 * Takes the learner's question and latest feedback, queries the Learning Rubric and
 * latest Attempt, then invokes the ACT_AnswerfromLatestFeedback prompt template to
 * generate a targeted coaching answer.
 *
 * Replaces Flow: ACT_Answer_from_Latest_Feedback
 * Planner action: ACT_AnswerfromLatestFeedback
 */
public with sharing class ActQA_Gateway {

  private static final String ACTION_NAME = 'AnswerFromLatestFeedback';

  public class Request {
    @InvocableVariable(
      label='Latest Feedback'
      description='The human-readable feedback text previously retrieved by the Get Learner Latest Feedback action. Passed as context to the prompt template for answer generation.'
      required=true
    )
    public String latestFeedback;

    @InvocableVariable(
      label='Learner Question'
      description='The question asked by the learner about their feedback, e.g. "Why did I fail?" or "What is my score?" The prompt template uses this to determine which section of analysis to return.'
      required=true
    )
    public String learnerQuestion;

    @InvocableVariable(
      label='Learning Rubric ID'
      description='The Learning_Rubric__c record Id. Used to retrieve the rubric record (guidelines, golden script, passing score) and the latest Attempt record for the prompt template.'
      required=true
    )
    public String learningrubricId;
  }

  @InvocableMethod(
    label='Answer From Latest Feedback'
    description='Takes the learner question and latest feedback, queries the Learning Rubric and latest Attempt, then invokes the ACT_AnswerfromLatestFeedback prompt template to generate a targeted coaching answer.'
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
      // Query the Learning Rubric (full record for prompt template)
      List<Learning_Rubric__c> rubrics = [
        SELECT Id, Name, Latest_Feedback__c, Guidelines_Text__c,
               Golden_Script__c, Passing_Score__c, Overall_Score_0_10__c
        FROM Learning_Rubric__c
        WHERE Id = :req.learningrubricId
        LIMIT 1
      ];
      if (rubrics.isEmpty()) {
        return ActGateway_Responses.fromError(
          ACTION_NAME,
          'Learning Rubric not found for Id: ' + req.learningrubricId,
          new List<String>{ 'Verify the Learning Rubric Id is correct.' },
          AgentCore_Constants.RESULT_CODE_NOT_FOUND
        );
      }
      Learning_Rubric__c rubric = rubrics[0];

      // Query the latest Attempt (full record for prompt template)
      List<Attempt__c> attempts = [
        SELECT Id, Transcript_Text__c, Feedback_Summary__c, Overall_Score__c, CreatedDate
        FROM Attempt__c
        WHERE Learning_Rubric__c = :req.learningrubricId
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      if (attempts.isEmpty()) {
        // No attempt — return empty answer
        Map<String, Object> data = new Map<String, Object>{ 'agentAnswer' => '' };
        Map<String, Object> envelope = AgentCore_Response.buildSuccess(
          ACTION_NAME,
          new List<Map<String, Object>>{ data },
          null
        );
        envelope.put(AgentCore_Response.FIELD_SUMMARY, 'No attempt found for this Learning Rubric.');
        return new ActGateway_Responses.GatewayResponse(envelope);
      }
      Attempt__c attempt = attempts[0];

      // Call the ACT_AnswerfromLatestFeedback prompt template
      String agentAnswer = generateCoachingAnswer(req.learnerQuestion, req.latestFeedback, rubric, attempt);

      Map<String, Object> data = new Map<String, Object>{
        'agentAnswer' => agentAnswer
      };
      Map<String, Object> envelope = AgentCore_Response.buildSuccess(
        ACTION_NAME,
        new List<Map<String, Object>>{ data },
        null
      );
      envelope.put(AgentCore_Response.FIELD_SUMMARY, 'Coaching answer generated for the learner question.');
      return new ActGateway_Responses.GatewayResponse(envelope);

    } catch (Exception e) {
      return ActGateway_Responses.fromError(
        ACTION_NAME,
        'Failed to generate answer: ' + e.getMessage(),
        new List<String>{ 'Verify the Learning Rubric and feedback data are valid.' }
      );
    }
  }

  private static String generateCoachingAnswer(
    String learnerQuestion,
    String latestFeedback,
    Learning_Rubric__c rubric,
    Attempt__c attempt
  ) {
    if (AgentCore_Response.isApexTestContext()) {
      return 'Test coaching answer';
    }
    try {
      ConnectApi.EinsteinPromptTemplateGenerationsInput ptInput =
        new ConnectApi.EinsteinPromptTemplateGenerationsInput();
      ptInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
      ptInput.additionalConfig.applicationName = 'ActQA_Gateway';
      ptInput.isPreview = false;

      Map<String, ConnectApi.WrappedValue> inputParams =
        new Map<String, ConnectApi.WrappedValue>();

      ConnectApi.WrappedValue questionVal = new ConnectApi.WrappedValue();
      questionVal.value = learnerQuestion;
      inputParams.put('Input:learnerQuestion', questionVal);

      ConnectApi.WrappedValue feedbackVal = new ConnectApi.WrappedValue();
      feedbackVal.value = latestFeedback;
      inputParams.put('Input:latestFeedback', feedbackVal);

      ConnectApi.WrappedValue attemptVal = new ConnectApi.WrappedValue();
      attemptVal.value = attempt;
      inputParams.put('Input:learnerAttempt', attemptVal);

      ConnectApi.WrappedValue rubricVal = new ConnectApi.WrappedValue();
      rubricVal.value = rubric;
      inputParams.put('Input:LearningRubric_c', rubricVal);

      ptInput.inputParams = inputParams;

      ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
        ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
          'ACT_AnswerfromLatestFeedback', ptInput
        );
      if (result != null && result.generations != null && !result.generations.isEmpty()) {
        return result.generations[0].text;
      }
    } catch (Exception e) {
      throw new AgentCore_Exception('Prompt template invocation failed: ' + e.getMessage());
    }
    return '';
  }
}
