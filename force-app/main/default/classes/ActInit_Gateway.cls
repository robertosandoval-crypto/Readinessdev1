/**
 * @description Invocable handler for initializing a Sales Coach session.
 * Retrieves the logged-in user, their active Learner Profile, the Learning Rubric
 * for the current record, and the latest Attempt. Returns structured error messages
 * for wrong rubric, no attempt, or missing transcript states.
 *
 * Replaces Flow: ACT_Get_Logged_in_User
 * Planner action: ACT_Get_LoggedinUser_and_LearningRubricandAttempt
 */
public with sharing class ActInit_Gateway {

  private static final String ACTION_NAME = 'InitSalesCoachSession';

  public class Request {
    @InvocableVariable(
      label='User ID'
      description='The Salesforce User Id of the logged-in learner. Defaults to the running user if left blank.'
      required=false
    )
    public String userId;

    @InvocableVariable(
      label='Record ID'
      description='The Learning_Rubric__c record Id from the current page context (currentRecordId). Required to identify which Sales Coach Assessment to load.'
      required=true
    )
    public String varRecordId;
  }

  @InvocableMethod(
    label='Initialize Sales Coach Session'
    description='Retrieves the logged-in user, their active Learner Profile, the Learning Rubric for the current record, and the latest Attempt. Returns error messages for wrong rubric, no attempt, or missing transcript states.'
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
      // Resolve userId — default to running user
      String resolvedUserId = String.isBlank(req.userId) ? UserInfo.getUserId() : req.userId;
      String userName = UserInfo.getFirstName();

      // Get user's first name if not the running user
      if (resolvedUserId != UserInfo.getUserId()) {
        List<User> users = [SELECT FirstName FROM User WHERE Id = :resolvedUserId LIMIT 1];
        if (!users.isEmpty()) {
          userName = users[0].FirstName;
        }
      }

      // Get active Learner Profile
      List<SObject> profiles = [
        SELECT Id FROM Learner_Profile__c
        WHERE User__c = :resolvedUserId AND Status__c = 'Active'
        LIMIT 1
      ];
      if (profiles.isEmpty()) {
        return buildWrongRubricResponse();
      }
      Id learnerProfileId = profiles[0].Id;

      // Get Learning Rubric matching the record ID and learner profile
      List<SObject> rubrics = [
        SELECT Id, Name FROM Learning_Rubric__c
        WHERE Learner_Profile__c = :learnerProfileId AND Id = :req.varRecordId
        LIMIT 1
      ];
      if (rubrics.isEmpty()) {
        return buildWrongRubricResponse();
      }
      String learningRubricId = String.valueOf(rubrics[0].Id);
      String learningRubricName = (String) rubrics[0].get('Name');

      // Get latest Attempt
      List<SObject> attempts = [
        SELECT Id, Transcript_Text__c FROM Attempt__c
        WHERE Learning_Rubric__c = :rubrics[0].Id
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      if (attempts.isEmpty()) {
        return buildNoAttemptResponse();
      }

      // Check if transcript exists
      String transcript = (String) attempts[0].get('Transcript_Text__c');
      if (String.isBlank(transcript)) {
        return buildMissingTranscriptResponse();
      }

      // Success — return session data
      Map<String, Object> data = new Map<String, Object>{
        'userName' => userName,
        'learningRubricId' => learningRubricId,
        'learningRubricName' => learningRubricName,
        'learnerProfileId' => String.valueOf(learnerProfileId)
      };
      Map<String, Object> envelope = AgentCore_Response.buildSuccess(
        ACTION_NAME,
        new List<Map<String, Object>>{ data },
        null
      );
      envelope.put(
        AgentCore_Response.FIELD_SUMMARY,
        'Session initialized for ' + userName + ' on assessment "' + learningRubricName + '".'
      );
      return new ActGateway_Responses.GatewayResponse(envelope);

    } catch (Exception e) {
      return ActGateway_Responses.fromError(
        ACTION_NAME,
        'Failed to initialize session: ' + e.getMessage(),
        new List<String>{ 'Verify you have an active Learner Profile and are on a valid Sales Coach Assessment.' }
      );
    }
  }

  private static ActGateway_Responses.GatewayResponse buildWrongRubricResponse() {
    String errorHtml = '<p>Sorry you\'re facing the Error because:</p>'
      + '<p>1. You are not on your Sales Coach Assessment, please navigate to your Sales Coach Assessment.</p>'
      + '<p>2. You might not have an Active Learner Profile. If you need additional help go to '
      + '<a href="https://salesforce.enterprise.slack.com/archives/C01SFA61CP4">#help-act</a> on slack.</p>';

    Map<String, Object> data = new Map<String, Object>{
      'outWrongLearningRubric' => errorHtml
    };
    Map<String, Object> envelope = AgentCore_Response.buildError(
      ACTION_NAME,
      'User is not on a valid Sales Coach Assessment or does not have an active Learner Profile.',
      new List<String>{
        'Navigate to your Sales Coach Assessment.',
        'Verify you have an active Learner Profile.'
      },
      AgentCore_Constants.RESULT_CODE_NOT_FOUND
    );
    envelope.put(AgentCore_Response.FIELD_DATA, new List<Map<String, Object>>{ data });
    return new ActGateway_Responses.GatewayResponse(envelope);
  }

  private static ActGateway_Responses.GatewayResponse buildNoAttemptResponse() {
    String errorHtml = '<p>You don\'t currently have an attempt recorded on this Sales Coach Assessment. '
      + 'Sometimes technical issues can prevent a session from saving properly. Common reasons include:</p>'
      + '<ul><li>The video being too short</li><li>Audio glitches</li>'
      + '<li>Refreshing your browser tab mid-session</li>'
      + '<li>A temporary dip in your internet connection</li></ul>'
      + '<p>To avoid these issues, make sure you meet the minimum time requirement, have clear audio, '
      + 'avoid refreshing your tab during the assessment, and maintain a stable internet connection. '
      + 'Give it another shot, and if problems persist, let me know—I\'d be happy to open a case for you!</p>';

    Map<String, Object> data = new Map<String, Object>{
      'outNoAttemptReasons' => errorHtml
    };
    Map<String, Object> envelope = AgentCore_Response.buildError(
      ACTION_NAME,
      'No attempt recorded on this Sales Coach Assessment.',
      new List<String>{
        'Complete an attempt on the assessment first.',
        'Check for audio/video issues and try again.'
      },
      AgentCore_Constants.RESULT_CODE_NOT_FOUND
    );
    envelope.put(AgentCore_Response.FIELD_DATA, new List<Map<String, Object>>{ data });
    return new ActGateway_Responses.GatewayResponse(envelope);
  }

  private static ActGateway_Responses.GatewayResponse buildMissingTranscriptResponse() {
    // Call the ACT_Missing_Transcript prompt template for troubleshooting steps
    String transcriptMessage = '';
    if (!AgentCore_Response.isApexTestContext()) {
      try {
        // Query the knowledge article for troubleshooting steps
        List<SObject> articles = [
          SELECT Id, Title, ArticleNumber FROM Knowledge__kav
          WHERE ArticleNumber = '000002740'
          LIMIT 1
        ];
        if (!articles.isEmpty()) {
          ConnectApi.EinsteinPromptTemplateGenerationsInput ptInput =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
          ptInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
          ptInput.additionalConfig.applicationName = 'ActInit_Gateway';
          ptInput.isPreview = false;

          Map<String, ConnectApi.WrappedValue> inputParams =
            new Map<String, ConnectApi.WrappedValue>();
          ConnectApi.WrappedValue knowledgeVal = new ConnectApi.WrappedValue();
          knowledgeVal.value = articles[0];
          inputParams.put('Input:knowledge', knowledgeVal);
          ptInput.inputParams = inputParams;

          ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
              'ACT_Missing_Transcript', ptInput
            );
          if (result != null && result.generations != null && !result.generations.isEmpty()) {
            transcriptMessage = result.generations[0].text;
          }
        }
      } catch (Exception e) {
        transcriptMessage = 'Transcript is missing from your latest attempt. Please try recording your session again.';
      }
    } else {
      transcriptMessage = 'Transcript is missing from your latest attempt. Please try recording your session again.';
    }

    Map<String, Object> data = new Map<String, Object>{
      'outTranscriptMissing' => transcriptMessage
    };
    Map<String, Object> envelope = AgentCore_Response.buildError(
      ACTION_NAME,
      'Transcript is missing from the latest attempt.',
      new List<String>{ 'Follow the troubleshooting steps to resolve the transcript issue.' },
      AgentCore_Constants.RESULT_CODE_NOT_FOUND
    );
    envelope.put(AgentCore_Response.FIELD_DATA, new List<Map<String, Object>>{ data });
    return new ActGateway_Responses.GatewayResponse(envelope);
  }
}
