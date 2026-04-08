/**
 * @description Shared response and request DTOs for ACT Sales Coach gateway handlers.
 * Provides the common @InvocableVariable output pattern used by all gateway classes
 * to return a deterministic AgentCore_Response JSON envelope.
 */
public with sharing class ActGateway_Responses {

  /**
   * @description Standard gateway response wrapper.
   * All gateway handlers return this with a single serialized JSON envelope
   * so the GenAI planner receives a deterministic, parseable response.
   */
  public class GatewayResponse {
    @InvocableVariable(
      label='Response JSON'
      description='A JSON envelope containing the action result. Parse the "ok" field (true/false) to determine success or error. On success the "data" array contains result records and "summary" describes the outcome. On error "error" contains the message and "suggestions" contains recovery steps.'
      required=true
    )
    public String responseJson;

    public GatewayResponse() {
    }

    public GatewayResponse(Map<String, Object> envelope) {
      this.responseJson = AgentCore_Response.serializeEnvelope(envelope);
    }
  }

  /**
   * @description Helper to build a GatewayResponse from a success envelope.
   */
  public static GatewayResponse fromSuccess(String action, List<Map<String, Object>> data, Map<String, Object> meta) {
    return new GatewayResponse(AgentCore_Response.buildSuccess(action, data, meta));
  }

  /**
   * @description Helper to build a GatewayResponse from an error envelope.
   */
  public static GatewayResponse fromError(String action, String error, List<String> suggestions) {
    return new GatewayResponse(AgentCore_Response.buildError(action, error, suggestions));
  }

  /**
   * @description Helper to build a GatewayResponse from an error envelope with a specific code.
   */
  public static GatewayResponse fromError(String action, String error, List<String> suggestions, String resultCode) {
    return new GatewayResponse(AgentCore_Response.buildError(action, error, suggestions, resultCode));
  }
}
