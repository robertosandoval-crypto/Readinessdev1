/**
 * @description Permission validation framework for AgentCore gateway handlers.
 * Provides preflight permission checks and action evaluation for AI agent actions.
 */
public with sharing class AgentCore_PermissionValidator {

  /**
   * @description Result of a single permission check.
   */
  public class PermissionResult {
    public Boolean allowed;

    public PermissionResult() {
      this.allowed = true;
    }
  }

  /**
   * @description Evaluation of a specific action's permission requirements.
   */
  public class ActionEvaluation {
    public String actionKey;
    public Boolean allowed;
    public List<String> requiredCustomPermissions;
    public List<String> missingCustomPermissions;
    public String message;
    public List<String> suggestions;

    public ActionEvaluation() {
      this.allowed = true;
      this.requiredCustomPermissions = new List<String>();
      this.missingCustomPermissions = new List<String>();
      this.message = '';
      this.suggestions = new List<String>();
    }

    public Map<String, Object> toMap() {
      return new Map<String, Object>{
        'actionKey' => this.actionKey,
        'allowed' => this.allowed,
        'requiredCustomPermissions' => this.requiredCustomPermissions,
        'missingCustomPermissions' => this.missingCustomPermissions,
        'message' => this.message,
        'suggestions' => this.suggestions
      };
    }
  }

  /**
   * @description Unified result combining permission check, validation, and action evaluation.
   */
  public class UnifiedPreFlightResult {
    public Boolean allowed;
    public PermissionResult permissionResult;
    public ActionEvaluation actionEvaluation;
    public Map<String, Object> permissionInfo;
    public AgentCore_Validation.SearchValidationResult validationResult;
    public String validationMessage;
    public List<String> suggestions;

    public UnifiedPreFlightResult() {
      this.allowed = true;
      this.suggestions = new List<String>();
      this.permissionInfo = new Map<String, Object>();
    }

    public String getErrorMessage() {
      if (String.isNotBlank(this.validationMessage)) {
        return this.validationMessage;
      }
      if (this.actionEvaluation != null && String.isNotBlank(this.actionEvaluation.message)) {
        return this.actionEvaluation.message;
      }
      return 'Permission check failed.';
    }
  }
}
