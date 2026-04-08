/**
 * @description Invocable handler for creating and routing support cases.
 * Creates a support case for the learner, assigns it to the Tier 1 Support queue,
 * and returns the created case details in a deterministic response envelope.
 *
 * Replaces Flow: ACT_Create_and_Route_Support_Case
 * Planner action: ACT_Case_Escalation
 */
public with sharing class ActCase_Gateway {

  private static final String ACTION_NAME = 'CreateSupportCase';

  public class Request {
    @InvocableVariable(
      label='Case Description'
      description='The description for the support case. Should be auto-generated from the conversation context and confirmed by the learner before submission.'
      required=true
    )
    public String caseDescription;

    @InvocableVariable(
      label='Case Subject'
      description='The subject line for the support case. Should be auto-generated from the conversation context and confirmed by the learner. Will be appended with the Learning Rubric name.'
      required=true
    )
    public String caseSubject;

    @InvocableVariable(
      label='User ID'
      description='The Salesforce User Id of the learner. Used to look up the Learner Profile for case association. Defaults to the running user if left blank.'
      required=false
    )
    public String userId;

    @InvocableVariable(
      label='Learning Rubric ID'
      description='The Learning_Rubric__c record Id from the context variable learningRubricId. Used to associate the case with the correct assessment and append the rubric name to the case subject.'
      required=true
    )
    public String varLearningRubricId;
  }

  @InvocableMethod(
    label='Create Support Case'
    description='Creates a support case for the learner, assigns it to the Tier 1 Support queue, and returns the created case details. Requires an active Learner Profile.'
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
        return ActGateway_Responses.fromError(
          ACTION_NAME,
          'No active Learner Profile found for this user.',
          new List<String>{ 'Verify the user has an active Learner Profile.' },
          AgentCore_Constants.RESULT_CODE_NOT_FOUND
        );
      }
      Id learnerProfileId = profiles[0].Id;

      // Get Support Queue
      List<Group> queues = [
        SELECT Id FROM Group
        WHERE Type = 'Queue' AND Name LIKE '%Tier 1 Support%'
        LIMIT 1
      ];
      if (queues.isEmpty()) {
        return ActGateway_Responses.fromError(
          ACTION_NAME,
          'Tier 1 Support queue not found.',
          new List<String>{ 'Contact your administrator to set up the Tier 1 Support queue.' }
        );
      }

      // Get Learning Rubric for the subject line
      List<SObject> rubrics = [
        SELECT Id, Name FROM Learning_Rubric__c
        WHERE Learner_Profile__c = :learnerProfileId AND Id = :req.varLearningRubricId
        LIMIT 1
      ];
      String rubricName = '';
      if (!rubrics.isEmpty()) {
        rubricName = (String) rubrics[0].get('Name');
      }

      // Build subject with rubric name appended
      String fullSubject = req.caseSubject + ' : ' + rubricName;

      // Create the Case
      Case newCase = new Case(
        Description = req.caseDescription,
        Subject = fullSubject,
        Learner_Profile__c = learnerProfileId,
        OwnerId = queues[0].Id,
        Priority = 'Medium'
      );
      insert newCase;

      // Re-query for display fields
      Case createdCase = [
        SELECT Id, CaseNumber, Subject, Description, Status, Priority, CreatedDate, Learner_Profile__c
        FROM Case
        WHERE Id = :newCase.Id
        LIMIT 1
      ];

      // Build response data
      Set<String> caseFields = new Set<String>{
        'Id', 'CaseNumber', 'Subject', 'Description', 'Status', 'Priority', 'CreatedDate', 'Learner_Profile__c'
      };
      Map<String, Object> caseData = AgentCore_Response.objectToMap(createdCase, caseFields);
      Map<String, Object> envelope = AgentCore_Response.buildSuccess(
        ACTION_NAME,
        new List<Map<String, Object>>{ caseData },
        null
      );
      envelope.put(
        AgentCore_Response.FIELD_SUMMARY,
        'Support case ' + createdCase.CaseNumber + ' created and assigned to Tier 1 Support.'
      );
      return new ActGateway_Responses.GatewayResponse(envelope);

    } catch (Exception e) {
      return ActGateway_Responses.fromError(
        ACTION_NAME,
        'Failed to create support case: ' + e.getMessage(),
        new List<String>{ 'Verify you have an active Learner Profile and valid Learning Rubric.' }
      );
    }
  }
}
