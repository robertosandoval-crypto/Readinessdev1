/**
 * @description Validation utilities for AgentCore gateway handlers.
 * Provides input validation and search parameter validation for AI agent actions.
 */
public with sharing class AgentCore_Validation {

  /**
   * @description Result of validating search parameters against an SObject schema.
   */
  public class SearchValidationResult {
    public Boolean isValid;
    public List<String> globalErrors;
    public List<Map<String, Object>> errors;
    public List<String> sampleRecords;

    public SearchValidationResult() {
      this.isValid = true;
      this.globalErrors = new List<String>();
      this.errors = new List<Map<String, Object>>();
      this.sampleRecords = new List<String>();
    }
  }
}
