/**
 * @description Builds standardized responses for AI agents with schema-aware,
 * AI-friendly response structures that work with the single output invocable
 * variable constraint of GenAI functions.
 */
public with sharing class AgentCore_Response {
  public static final String FIELD_OK = AgentCore_Constants.AI_FIELD_OK;
  public static final String FIELD_ACTION = AgentCore_Constants.AI_FIELD_ACTION;
  public static final String FIELD_DATA = AgentCore_Constants.AI_FIELD_DATA;
  public static final String FIELD_META = AgentCore_Constants.AI_FIELD_META;
  public static final String FIELD_ERROR = AgentCore_Constants.AI_FIELD_ERROR;
  public static final String FIELD_SUGGESTIONS = AgentCore_Constants.AI_FIELD_SUGGESTIONS;
  public static final String FIELD_SCHEMA = AgentCore_Constants.AI_FIELD_SCHEMA;
  public static final String FIELD_PERMISSIONS = AgentCore_Constants.AI_FIELD_PERMISSIONS;
  public static final String FIELD_SUMMARY = AgentCore_Constants.AI_FIELD_SUMMARY;
  public static final String FIELD_HEADER = AgentCore_Constants.AI_FIELD_HEADER;
  public static final String FIELD_NEXT = AgentCore_Constants.AI_FIELD_NEXT;
  public static final String FIELD_OPERATION = 'operation';

  private static final Integer MAX_SUGGESTIONS = 5;
  private static final Integer MAX_NEXT = 3;
  private static final Integer MAX_SUGGESTION_LENGTH = 120;

  private static final String DEFAULT_ACTION = 'Unknown';
  private static final String DEFAULT_ERROR = 'An unknown error occurred';
  private static final String DEFAULT_SUCCESS_SUMMARY = 'Operation completed successfully.';
  private static final String DEFAULT_ERROR_SUMMARY = 'Request failed.';
  private static final String DEFAULT_SUGGESTION_CHECK_INPUT = 'Please check your input and try again';
  private static final String DEFAULT_SUGGESTION_GENERIC = 'Please resubmit with valid parameters.';
  private static final String DEFAULT_SUGGESTION_PERMISSION = 'Contact your administrator to request access.';
  private static final String DEFAULT_SUGGESTION_NOT_FOUND = 'Verify the record exists and you have access.';

  /**
   * @description Converts an object to a Map<String, Object> filtering for allowed fields.
   * Useful for converting SObjects or untyped objects into clean maps for response payloads.
   * @param obj The object to convert (SObject or Apex Object)
   * @param allowedFields Set of field names to include in the result
   * @return Map containing only the allowed fields with their values
   * @throws AgentCore_Exception if conversion fails
   */
  public static Map<String, Object> objectToMap(Object obj, Set<String> allowedFields) {
    Map<String, Object> result = new Map<String, Object>();
    if (obj == null || allowedFields == null || allowedFields.isEmpty()) {
      return result;
    }
    try {
      Map<String, Object> fullMap = (Map<String, Object>) System.JSON.deserializeUntyped(
        System.JSON.serialize(obj)
      );
      for (String field : allowedFields) {
        if (fullMap.containsKey(field) && fullMap.get(field) != null) {
          result.put(field, fullMap.get(field));
        }
      }
    } catch (Exception e) {
      String typeName = obj == null
        ? 'null'
        : (obj instanceof SObject
          ? ((SObject) obj).getSObjectType().getDescribe().getName()
          : String.valueOf(obj));
      String expected = 'Serializable object with fields: ' + String.join(new List<String>(allowedFields), ', ');
      throw new AgentCore_Exception(
        'Failed to convert object to map. Object type: ' +
        typeName +
        '. Expected: ' +
        expected +
        '. Error: ' +
        e.getMessage()
      );
    }
    return result;
  }

  /**
   * @description Builds a standard success response envelope.
   * @param action The action key associated with the request
   * @param data List of data records (Maps) to include
   * @param meta Metadata map to include (e.g., recordCount, timestamp)
   * @return Normalized response envelope with success=true
   */
  public static Map<String, Object> buildSuccess(
    String action,
    List<Map<String, Object>> data,
    Map<String, Object> meta
  ) {
    String resolvedAction = String.isBlank(action) ? DEFAULT_ACTION : action;
    List<Map<String, Object>> safeData = data == null ? new List<Map<String, Object>>() : data;
    Map<String, Object> metaMap = meta == null ? new Map<String, Object>() : new Map<String, Object>(meta);
    if (!metaMap.containsKey('recordCount')) {
      metaMap.put('recordCount', safeData.size());
    }
    Map<String, Object> response = new Map<String, Object>{
      FIELD_OK => true,
      'success' => true,
      FIELD_ACTION => resolvedAction,
      FIELD_DATA => safeData,
      FIELD_META => metaMap,
      'code' => AgentCore_Constants.RESULT_CODE_OK,
      'status' => AgentCore_Constants.RESULT_CODE_OK
    };
    return normalizeEnvelope(response);
  }

  /**
   * @description Centralized test-context check.
   * Keep Test.isRunningTest() calls confined to allowlisted core utilities.
   */
  public static Boolean isApexTestContext() {
    return Test.isRunningTest();
  }

  /**
   * @description Builds a standard error response envelope with default INPUT_INVALID code.
   * @param action The action key associated with the request
   * @param error The error message
   * @param suggestions List of actionable suggestions for the user/agent
   * @return Normalized response envelope with success=false
   */
  public static Map<String, Object> buildError(
    String action,
    String error,
    List<String> suggestions
  ) {
    return buildError(
      action,
      error,
      suggestions,
      AgentCore_Constants.RESULT_CODE_INPUT_INVALID
    );
  }

  /**
   * @description Builds a standard error response envelope with a specific result code.
   * @param action The action key associated with the request
   * @param error The error message
   * @param suggestions List of actionable suggestions
   * @param resultCode The specific result code (e.g., NOT_FOUND, PERMISSION_DENIED)
   * @return Normalized response envelope
   */
  public static Map<String, Object> buildError(
    String action,
    String error,
    List<String> suggestions,
    String resultCode
  ) {
    String resolvedAction = String.isBlank(action) ? DEFAULT_ACTION : action;
    String errorMessage = String.isBlank(error) ? DEFAULT_ERROR : error;
    List<String> suggestionList = ensureSuggestions(
      suggestions,
      DEFAULT_SUGGESTION_CHECK_INPUT
    );

    Map<String, Object> response = new Map<String, Object>{
      FIELD_OK => false,
      'success' => false,
      FIELD_ACTION => resolvedAction,
      FIELD_DATA => new List<Map<String, Object>>(),
      FIELD_META => new Map<String, Object>{ 'recordCount' => 0 },
      FIELD_ERROR => errorMessage,
      FIELD_SUGGESTIONS => suggestionList,
      FIELD_SUMMARY => errorMessage
    };
    response.put('code', String.isBlank(resultCode) ? AgentCore_Constants.RESULT_CODE_ERROR : resultCode);
    response.put('status', AgentCore_Constants.RESULT_CODE_ERROR);
    response.put('message', errorMessage);
    response.put('errors', new List<String>{ errorMessage });
    return normalizeEnvelope(response);
  }

  /**
   * @description Builds a standardized TOO_LARGE error response.
   * @param action The action key
   * @param actual Actual number of records/items
   * @param max Maximum allowed limit
   * @param type Context label (unused but kept for signature)
   * @return Error envelope with TOO_LARGE code
   */
  public static Map<String, Object> buildTooLargeError(
    String action,
    Integer actual,
    Integer max,
    String type
  ) {
    String dataType = String.isBlank(type) ? 'records' : type;
    String error =
      'Data too large: requested ' +
      String.valueOf(actual) +
      ' ' +
      dataType +
      ' exceeds maximum of ' +
      String.valueOf(max) +
      '.';
    List<String> suggestions = new List<String>{
      'Reduce the number of ' + dataType + ' requested.'
    };
    return buildError(action, error, suggestions, AgentCore_Constants.RESULT_CODE_TOO_LARGE);
  }

  /**
   * @description Enriches a response envelope with schema metadata for the target object.
   * Adds field labels, types, and updateability flags to help AI agents understand the data structure.
   * @param response The response envelope to enrich (modified in place)
   * @param sobjectType The SObject type to describe
   * @param fields Set of field API names to include in the schema description
   * @return The modified response envelope
   */
  public static Map<String, Object> addSchemaInfo(
    Map<String, Object> response,
    Schema.SObjectType sobjectType,
    Set<String> fields
  ) {
    if (response == null || sobjectType == null || fields == null || fields.isEmpty()) {
      return response;
    }
    try {
      Schema.DescribeSObjectResult describe = sobjectType.getDescribe();
      Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();
      Map<String, Object> schemaInfo = new Map<String, Object>{
        'objectName' => describe.getName(),
        'objectLabel' => describe.getLabel()
      };
      Map<String, Object> fieldSchemas = new Map<String, Object>();
      for (String fieldName : fields) {
        if (fieldMap.containsKey(fieldName)) {
          Schema.DescribeFieldResult f = fieldMap.get(fieldName).getDescribe();
          fieldSchemas.put(
            fieldName,
            new Map<String, Object>{
              'label' => f.getLabel(),
              'type' => String.valueOf(f.getType()),
              'required' => !f.isNillable(),
              'updateable' => f.isUpdateable()
            }
          );
        }
      }
      schemaInfo.put('fields', fieldSchemas);
      response.put(FIELD_SCHEMA, schemaInfo);
      return response;
    } catch (Exception e) {
      String typeName = sobjectType == null ? 'null' : String.valueOf(sobjectType);
      throw new AgentCore_Exception(
        'Failed to add schema info. Object type: ' +
        typeName +
        '. Expected: Valid sObjectType with describe metadata. Error: ' +
        e.getMessage()
      );
    }
  }

  /**
   * @description Determines if a result code represents a success or failure.
   * Treats OK and PARTIAL_SUCCESS as success. NOT_FOUND is treated as success for read/search actions.
   * @param action The action key
   * @param code The result code to evaluate
   * @return True if the code/action combination is considered a success
   */
  public static Boolean successPolicy(String action, String code) {
    if (code == AgentCore_Constants.RESULT_CODE_OK) {
      return true;
    }
    if (code == AgentCore_Constants.RESULT_CODE_PARTIAL_SUCCESS) {
      return true;
    }
    if (
      code == AgentCore_Constants.RESULT_CODE_NOT_FOUND &&
      !String.isBlank(action) &&
      (action.containsIgnoreCase('retrieve') ||
        action.containsIgnoreCase('search') ||
        action.containsIgnoreCase('read') ||
        action.containsIgnoreCase('get') ||
        action.containsIgnoreCase('details') ||
        action.containsIgnoreCase('describe'))
    ) {
      return true;
    }
    return false;
  }

  /**
   * @description Ensures a response envelope contains all required contract fields.
   * Adds missing fields like ok, success, status, code, data, meta, permissions, and summary.
   * @param env The raw envelope map
   * @return The normalized envelope map
   */
  public static Map<String, Object> normalizeEnvelope(Map<String, Object> env) {
    if (env == null) {
      env = new Map<String, Object>();
    }

    String action = env.containsKey(FIELD_ACTION)
      ? String.valueOf(env.get(FIELD_ACTION))
      : null;
    if (String.isBlank(action)) {
      action = DEFAULT_ACTION;
    }
    env.put(FIELD_ACTION, action);

    Object dataObj = env.get(FIELD_DATA);
    if (dataObj == null) {
      dataObj = new List<Map<String, Object>>();
    }
    Integer dataCount = dataSize(dataObj);
    env.put(FIELD_DATA, dataObj);

    Map<String, Object> meta = env.get(FIELD_META) instanceof Map<String, Object>
      ? (Map<String, Object>) env.get(FIELD_META)
      : new Map<String, Object>();
    if (dataCount == null) {
      dataCount = 0;
    }
    if (!meta.containsKey('recordCount')) {
      meta.put('recordCount', dataCount);
    }
    if (!meta.containsKey('dataCount')) {
      meta.put('dataCount', dataCount);
    }
    env.put(FIELD_META, meta);

    // PHASE 1 FIX: Always derive 'ok' from (action, code) using successPolicy,
    // EVEN IF the incoming envelope set ok incorrectly. This ensures contract consistency.
    String code = env.containsKey('code') ? String.valueOf(env.get('code')) : null;
    Boolean okHint = extractBoolean(env.get(FIELD_OK));
    code = canonicalizeCode(code, okHint);
    
    // Derive ok from code/action using successPolicy (authoritative source)
    Boolean ok;
    if (!String.isBlank(code)) {
      ok = successPolicy(action, code);
      // Override successPolicy for specific codes that must be false
      if (AgentCore_Constants.RESULT_CODE_PERMISSION_DENIED.equals(code)) {
        ok = false;
      }
      // PARTIAL_SUCCESS and NOT_FOUND (for retrieval actions) are already handled by successPolicy
    } else {
      // If no code, fall back to incoming ok/success/status as hint
      ok = okHint;
      if (ok == null) {
        Boolean success = extractBoolean(env.get('success'));
        if (success != null) {
          ok = success;
        } else if (env.containsKey('status')) {
          ok = AgentCore_Constants.RESULT_CODE_OK.equalsIgnoreCase(String.valueOf(env.get('status')));
        } else {
          ok = true; // Default to true if no indicators
        }
      }
      // Canonicalize code from ok if code was missing
      if (String.isBlank(code)) {
        code = ok ? AgentCore_Constants.RESULT_CODE_OK : AgentCore_Constants.RESULT_CODE_ERROR;
      }
    }
    env.put(FIELD_OK, ok);
    env.put('success', ok);
    env.put('status', ok ? AgentCore_Constants.RESULT_CODE_OK : AgentCore_Constants.RESULT_CODE_ERROR);
    env.put('code', code);

    Object summaryObj = env.containsKey(FIELD_SUMMARY) ? env.get(FIELD_SUMMARY) : null;
    Boolean summaryIsMap = summaryObj instanceof Map<String, Object>;
    String summaryText = summaryIsMap
      ? null
      : (summaryObj != null ? String.valueOf(summaryObj) : null);
    if (!summaryIsMap && String.isBlank(summaryText)) {
      if (env.containsKey(FIELD_ERROR) && !String.isBlank(String.valueOf(env.get(FIELD_ERROR)))) {
        summaryText = String.valueOf(env.get(FIELD_ERROR));
      } else {
        summaryText = ok ? DEFAULT_SUCCESS_SUMMARY : DEFAULT_ERROR_SUMMARY;
      }
    }
    if (!summaryIsMap) {
      env.put(FIELD_SUMMARY, summaryText);
    }

    if (!env.containsKey(FIELD_ERROR) && !ok) {
      String fallbackError = String.isBlank(summaryText)
        ? DEFAULT_ERROR_SUMMARY
        : summaryText;
      env.put(FIELD_ERROR, fallbackError);
    }

    Boolean hasSuggestions = env.containsKey(FIELD_SUGGESTIONS);
    List<String> suggestions = null;
    if (hasSuggestions || !ok) {
      suggestions = normalizeSuggestions(
        env.get(FIELD_SUGGESTIONS),
        ok,
        code
      );
      env.put(FIELD_SUGGESTIONS, suggestions);
    }

    if (suggestions != null && !suggestions.isEmpty()) {
      List<String> next = new List<String>();
      for (Integer i = 0; i < Math.min(MAX_NEXT, suggestions.size()); i++) {
        next.add(suggestions[i]);
      }
      env.put(FIELD_NEXT, next);
    } else if (!ok && !env.containsKey(FIELD_NEXT)) {
      // Ensure error envelopes always include actionable guidance.
      String fallback = defaultSuggestionForCode(code);
      if (String.isNotBlank(fallback)) {
        env.put(FIELD_SUGGESTIONS, new List<String>{ fallback });
        env.put(FIELD_NEXT, new List<String>{ fallback });
      }
    }

    Map<String, Object> permissions = normalizePermissions(env.get(FIELD_PERMISSIONS), action, code);
    env.put(FIELD_PERMISSIONS, permissions);
    if (!env.containsKey('actionEvaluation')) {
      env.put('actionEvaluation', permissions.get('actionEvaluation'));
    }
    if (!env.containsKey('permissionDenied')) {
      env.put('permissionDenied', permissions.get('permissionDenied'));
    }

    if (!env.containsKey(FIELD_HEADER) || String.isBlank(String.valueOf(env.get(FIELD_HEADER)))) {
      String headerSummary = summaryText;
      if (String.isBlank(headerSummary)) {
        headerSummary = ok ? DEFAULT_SUCCESS_SUMMARY : DEFAULT_ERROR_SUMMARY;
      }
      env.put(
        FIELD_HEADER,
        buildHeader(
          ok,
          code,
          headerSummary,
          env.containsKey(FIELD_ERROR) ? String.valueOf(env.get(FIELD_ERROR)) : null,
          suggestions,
          meta
        )
      );
    }

    return env;
  }

  /**
   * @description Normalizes and serializes a response envelope to JSON.
   * @param env The envelope map
   * @return JSON string representation of the normalized envelope
   */
  public static String serializeEnvelope(Map<String, Object> env) {
    Map<String, Object> normalized = normalizeEnvelope(env);
    JSONGenerator gen = JSON.createGenerator(true);
    gen.writeStartObject();

    List<String> ordered = new List<String>{
      FIELD_HEADER,
      FIELD_OK,
      'success',
      'status',
      'code',
      FIELD_ACTION
    };
    Set<String> knownFields = new Set<String>{
      FIELD_HEADER,
      FIELD_OK,
      'success',
      'status',
      'code',
      FIELD_ACTION,
      FIELD_NEXT,
      FIELD_SUGGESTIONS,
      FIELD_ERROR,
      'message',
      'errors',
      FIELD_PERMISSIONS,
      FIELD_META,
      FIELD_SCHEMA,
      FIELD_DATA,
      FIELD_SUMMARY
    };

    for (String field : ordered) {
      writeField(gen, field, normalized.get(field), true);
    }

    List<String> unknown = new List<String>();
    for (String key : normalized.keySet()) {
      if (!knownFields.contains(key)) {
        unknown.add(key);
      }
    }
    unknown.sort();
    for (String key : unknown) {
      writeField(gen, key, normalized.get(key), true);
    }

    writeField(gen, FIELD_NEXT, normalized.get(FIELD_NEXT), false);
    writeField(gen, FIELD_SUGGESTIONS, normalized.get(FIELD_SUGGESTIONS), false);
    writeField(gen, FIELD_ERROR, normalized.get(FIELD_ERROR), false);
    writeField(gen, 'message', normalized.get('message'), false);
    writeField(gen, 'errors', normalized.get('errors'), false);
    writeField(gen, FIELD_PERMISSIONS, normalized.get(FIELD_PERMISSIONS), true);
    writeField(gen, FIELD_META, normalized.get(FIELD_META), true);
    writeField(gen, FIELD_SCHEMA, normalized.get(FIELD_SCHEMA), false);
    writeField(gen, FIELD_DATA, normalized.get(FIELD_DATA), true);
    writeField(gen, FIELD_SUMMARY, normalized.get(FIELD_SUMMARY), true);

    gen.writeEndObject();
    return gen.getAsString();
  }

  /**
   * @description Safely parses a JSON string into a Map<String, Object>.
   * Returns an empty map if parsing fails.
   * @param json The JSON string to parse
   * @return Map representation of the JSON, or empty map on error
   */
  public static Map<String, Object> parse(String json) {
    if (String.isBlank(json)) {
      return new Map<String, Object>();
    }
    try {
      return (Map<String, Object>) System.JSON.deserializeUntyped(json);
    } catch (Exception e) {
      return new Map<String, Object>();
    }
  }

  /**
   * @description Extracts permission evaluation details from a preflight result.
   * @param preflight The unified preflight result
   * @return Map containing permission details (allowed, evaluated, actionEvaluation)
   */
  public static Map<String, Object> permissionsFromPreflight(
    AgentCore_PermissionValidator.UnifiedPreFlightResult preflight
  ) {
    if (preflight == null) {
      return normalizePermissions(null, null, null);
    }

    Map<String, Object> permissions = new Map<String, Object>();
    if (preflight.permissionInfo != null) {
      permissions.putAll(preflight.permissionInfo);
    }

    Boolean allowed = preflight.permissionResult != null
      ? preflight.permissionResult.allowed
      : preflight.allowed;
    if (permissions.containsKey('allowed')) {
      Boolean allowedOverride = extractBoolean(permissions.get('allowed'));
      if (allowedOverride != null) {
        allowed = allowedOverride;
      }
    }

    permissions.put('allowed', allowed);
    permissions.put('evaluated', true);
    permissions.put('permissionDenied', !allowed);

    if (preflight.actionEvaluation != null) {
      permissions.put('actionEvaluation', preflight.actionEvaluation.toMap());
    }

    return normalizePermissions(permissions, null, null);
  }

  /**
   * @description Builds a failure response from a preflight check result.
   * Includes permission details and schema info to help agents self-correct.
   * @param action The action key
   * @param preflight The failed preflight result
   * @param type The SObject type
   * @param fields The fields involved in the check
   * @return Error response envelope with PERMISSION_DENIED or INPUT_INVALID code
   */
  public static Map<String, Object> buildPreflightFailure(
    String action,
    AgentCore_PermissionValidator.UnifiedPreFlightResult preflight,
    SObjectType type,
    Set<String> fields
  ) {
    String resultCode = AgentCore_Constants.RESULT_CODE_PERMISSION_DENIED;
    Boolean permissionAllowed = true;
    if (preflight != null) {
      if (preflight.permissionResult != null && preflight.permissionResult.allowed != null) {
        permissionAllowed = preflight.permissionResult.allowed;
      } else if (preflight.actionEvaluation != null && preflight.actionEvaluation.allowed != null) {
        permissionAllowed = preflight.actionEvaluation.allowed;
      } else if (preflight.permissionInfo != null && preflight.permissionInfo.containsKey('allowed')) {
        Boolean allowedFlag = extractBoolean(preflight.permissionInfo.get('allowed'));
        if (allowedFlag != null) {
          permissionAllowed = allowedFlag;
        }
      }
      if (permissionAllowed) {
        if (preflight.validationResult != null && preflight.validationResult.isValid == false) {
          resultCode = AgentCore_Constants.RESULT_CODE_INPUT_INVALID;
        } else if (!String.isBlank(preflight.validationMessage)) {
          resultCode = AgentCore_Constants.RESULT_CODE_INPUT_INVALID;
        }
      }
    }

    String errorMessage = preflight != null ? preflight.getErrorMessage() : DEFAULT_ERROR;
    List<String> suggestions = preflight != null ? preflight.suggestions : new List<String>();

    Map<String, Object> res = buildError(action, errorMessage, suggestions, resultCode);
    res.put(FIELD_PERMISSIONS, permissionsFromPreflight(preflight));
    return addSchemaInfo(res, type, fields);
  }

  /**
   * @description Extracts validation errors and sample record context as suggestions.
   * @param validationResult The search validation result
   * @param sobjectType The SObject type (unused context)
   * @return List of suggestion strings derived from validation errors
   */
  public static List<String> buildFieldSuggestions(
    AgentCore_Validation.SearchValidationResult validationResult,
    Schema.SObjectType sobjectType
  ) {
    List<String> suggestions = new List<String>();
    if (validationResult == null || sobjectType == null) {
      return suggestions;
    }

    if (validationResult.globalErrors != null) {
      for (String globalError : validationResult.globalErrors) {
        if (String.isNotBlank(globalError)) {
          suggestions.add(globalError);
        }
      }
    }

    if (validationResult.errors != null) {
      for (Map<String, Object> err : validationResult.errors) {
        if (err == null || !err.containsKey('messages')) {
          continue;
        }
        Object messagesObj = err.get('messages');
        if (messagesObj instanceof List<Object>) {
          for (Object msg : (List<Object>) messagesObj) {
            if (msg != null && String.isNotBlank(String.valueOf(msg))) {
              suggestions.add(String.valueOf(msg));
            }
          }
        }
      }
    }

    List<String> samples = validationResult.sampleRecords;
    if (samples != null && !samples.isEmpty()) {
      Boolean hasSampleError = false;
      for (String sample : samples) {
        if (sample != null && sample.startsWith('Sample query failed')) {
          suggestions.add(sample);
          hasSampleError = true;
          break;
        }
      }
      if (!hasSampleError) {
        suggestions.add('Example records: ' + String.join(samples, ' | '));
      }
    }

    return suggestions;
  }

  /**
   * @description Helper to format a standard field validation error message.
   * @param field The field name
   * @param val The invalid value
   * @param exp The expected format
   * @param ex Example of correct format (unused but kept for signature compatibility)
   * @return Formatted error string
   */
  public static String buildFieldValidationError(String field, Object val, String exp, String ex) {
    String received = val == null ? 'null' : String.valueOf(val);
    String message =
      'Validation error for field "' +
      String.valueOf(field) +
      '": You input "' +
      received +
      '". Expected format: ' +
      String.valueOf(exp) +
      '.';
    if (String.isNotBlank(ex)) {
      message += ' Example: ' + ex + '.';
    }
    message += ' Please resubmit with valid parameters.';
    return message;
  }

  /**
   * @description Helper to format a constraint violation error message.
   * @param field The field name
   * @param cons The constraint description
   * @param val The invalid value
   * @return Formatted error string
   */
  public static String buildConstraintError(String field, String cons, Object val) {
    String constraint = String.isBlank(cons) ? 'unknown' : cons;
    String received = val == null ? 'null' : String.valueOf(val);
    return
      'Constraint violation on field "' +
      String.valueOf(field) +
      '": You input "' +
      received +
      '". Expected: ' +
      constraint +
      '. Please resubmit with valid parameters.';
  }

  /**
   * @description Builds a standardized summary for search-style responses.
   * @param recordTypeLabel Label for the record type (e.g., "record", "checklist")
   * @param totalCount Total matched count, if known
   * @param returnedCount Number of records returned
   * @param sortFieldApiName Sort field API name (optional)
   * @param sortDescending Sort direction (optional)
   * @return Formatted summary string
   */
  public static String buildSearchSummary(
    String recordTypeLabel,
    Integer totalCount,
    Integer returnedCount,
    String sortFieldApiName,
    Boolean sortDescending
  ) {
    String label = String.isBlank(recordTypeLabel) ? 'record' : recordTypeLabel;
    Integer returnedSafe = returnedCount == null ? 0 : returnedCount;
    Integer totalSafe = totalCount == null ? returnedSafe : totalCount;
    String suffix = totalSafe == 1 ? '' : 's';
    String summary;
    if (totalCount != null && totalCount > returnedSafe) {
      summary =
        'Returned ' +
        String.valueOf(returnedSafe) +
        ' of ' +
        String.valueOf(totalSafe) +
        ' ' +
        label +
        suffix +
        '.';
    } else {
      summary =
        'Returned ' +
        String.valueOf(returnedSafe) +
        ' ' +
        label +
        suffix +
        '.';
    }
    if (String.isNotBlank(sortFieldApiName)) {
      String direction = sortDescending == null ? '' : (sortDescending ? ' (descending)' : ' (ascending)');
      summary =
        summary.substring(0, summary.length() - 1) +
        ' Sorted by ' +
        sortFieldApiName +
        direction +
        '.';
    }
    return summary;
  }

  public class ResponseBuilder {
    private Map<String, Object> response;
    private Boolean enforceSummary;
    private Boolean applyDefaultMeta;

    /**
     * @description Initializes a builder with base envelope structure.
     * @param success Initial success state
     * @param action The action key for the response
     */
    public ResponseBuilder(Boolean success, String action) {
      this.response = new Map<String, Object>{
        FIELD_OK => success,
        FIELD_ACTION => action,
        FIELD_DATA => new List<Map<String, Object>>(),
        FIELD_META => new Map<String, Object>()
      };
      // STEP 6.1 FIX: Explicitly set code based on success to ensure normalizeEnvelope() derives ok correctly
      if (success) {
        this.response.put('code', AgentCore_Constants.RESULT_CODE_OK);
      } else {
        this.response.put('code', AgentCore_Constants.RESULT_CODE_ERROR);
      }
      this.enforceSummary = false;
      this.applyDefaultMeta = false;
    }

    /**
     * @description Sets the data payload from a list of Maps.
     * @param data List of record maps
     * @return The builder instance
     */
    public ResponseBuilder withData(List<Map<String, Object>> data) {
      this.response.put(FIELD_DATA, data == null ? new List<Map<String, Object>>() : data);
      return this;
    }

    /**
     * @description Sets the data payload from a list of SObjects.
     * @param records List of SObject records
     * @return The builder instance
     */
    public ResponseBuilder withData(List<SObject> records) {
      this.response.put(FIELD_DATA, records == null ? new List<SObject>() : records);
      return this;
    }

    /**
     * @description Sets the data payload from a single Map record.
     * Wraps the map in a list automatically.
     * @param data Single record map
     * @return The builder instance
     */
    public ResponseBuilder withData(Map<String, Object> data) {
      if (data == null) {
        this.response.put(FIELD_DATA, new List<Map<String, Object>>());
      } else {
        this.response.put(FIELD_DATA, new List<Map<String, Object>>{ data });
      }
      return this;
    }

    /**
     * @description Sets the metadata map for the response.
     * @param meta Metadata key-value pairs
     * @return The builder instance
     */
    public ResponseBuilder withMeta(Map<String, Object> meta) {
      this.response.put(FIELD_META, meta == null ? new Map<String, Object>() : meta);
      return this;
    }

    /**
     * @description Sets the human-readable summary message.
     * @param summary Summary text
     * @return The builder instance
     */
    public ResponseBuilder withSummary(String summary) {
      this.response.put(FIELD_SUMMARY, summary);
      return this;
    }

    /**
     * @description Sets the result code (e.g., OK, ERROR, PERMISSION_DENIED).
     * @param code The result code string
     * @return The builder instance
     */
    public ResponseBuilder withCode(String code) {
      this.response.put('code', code);
      return this;
    }

    /**
     * @description Adds permission details from a preflight result.
     * @param pre UnifiedPreFlightResult to extract permissions from
     * @return The builder instance
     */
    public ResponseBuilder withPermissions(
      AgentCore_PermissionValidator.UnifiedPreFlightResult pre
    ) {
      this.response.put(FIELD_PERMISSIONS, permissionsFromPreflight(pre));
      return this;
    }

    /**
     * @description Adds permission details directly from a Map.
     * @param perms Permission details map
     * @return The builder instance
     */
    public ResponseBuilder withPermissions(Map<String, Object> perms) {
      this.response.put(FIELD_PERMISSIONS, perms);
      return this;
    }

    /**
     * @description Enriches the response with schema metadata.
     * @param t SObject Type
     * @param f Set of fields to describe
     * @return The builder instance
     */
    public ResponseBuilder withSchema(SObjectType t, Set<String> f) {
      addSchemaInfo(this.response, t, f);
      return this;
    }

    /**
     * @description Sets the operation type (e.g., READ, CREATE) in the metadata.
     * @param op Operation name
     * @return The builder instance
     */
    public ResponseBuilder withOperation(String op) {
      Map<String, Object> meta = this.response.get(FIELD_META) instanceof Map<String, Object>
        ? (Map<String, Object>) this.response.get(FIELD_META)
        : new Map<String, Object>();
      meta.put(FIELD_OPERATION, op);
      this.response.put(FIELD_META, meta);
      return this;
    }

    /**
     * @description Sets the error message field.
     * @param err Error text
     * @return The builder instance
     */
    public ResponseBuilder withError(String err) {
      this.response.put(FIELD_ERROR, err);
      return this;
    }

    /**
     * @description Sets the list of suggestions.
     * @param suggs List of suggestion strings
     * @return The builder instance
     */
    public ResponseBuilder withSuggestions(List<String> suggs) {
      this.response.put(FIELD_SUGGESTIONS, suggs);
      return this;
    }

    /**
     * @description Ensures a summary exists if missing.
     * @return The builder instance
     */
    public ResponseBuilder ensureSummary() {
      this.enforceSummary = true;
      return this;
    }

    /**
     * @description Adds default metadata if missing.
     * @return The builder instance
     */
    public ResponseBuilder withDefaultMeta() {
      this.applyDefaultMeta = true;
      return this;
    }

    /**
     * @description Adds pagination metadata to the response.
     * @param p Page number
     * @param s Page size
     * @param m Has more records flag
     * @return The builder instance
     */
    public ResponseBuilder withPagination(Integer p, Integer s, Boolean m) {
      Map<String, Object> meta = this.response.get(FIELD_META) instanceof Map<String, Object>
        ? (Map<String, Object>) this.response.get(FIELD_META)
        : new Map<String, Object>();
      meta.put('page', p == null ? 1 : p);
      meta.put('limit', s == null ? 0 : s);
      meta.put('hasMore', m == null ? false : m);
      this.response.put(FIELD_META, meta);
      return this;
    }

    /**
     * @description Finalizes and builds the response map, normalizing all fields.
     * @return The complete, normalized response envelope
     */
    public Map<String, Object> build() {
      if (applyDefaultMeta) {
        applyDefaultMeta(this.response);
      }
      if (enforceSummary) {
        String summary = this.response.containsKey(FIELD_SUMMARY)
          ? String.valueOf(this.response.get(FIELD_SUMMARY))
          : null;
        if (String.isBlank(summary)) {
          throw new AgentCore_Exception('Response summary is required');
        }
      }
      return normalizeEnvelope(this.response);
    }

    private void applyDefaultMeta(Map<String, Object> target) {
      Map<String, Object> meta = target.get(FIELD_META) instanceof Map<String, Object>
        ? (Map<String, Object>) target.get(FIELD_META)
        : new Map<String, Object>();
      if (!meta.containsKey('recordCount')) {
        Object dataObj = target.get(FIELD_DATA);
        List<Object> dataList = normalizeDataList(dataObj);
        meta.put('recordCount', dataList == null ? 0 : dataList.size());
      }
      if (!meta.containsKey('timestamp')) {
        meta.put('timestamp', DateTime.now());
      }
      target.put(FIELD_META, meta);
    }
  }

  /**
   * @description Creates a new ResponseBuilder initialized for success.
   * @param action The action key
   * @return A new ResponseBuilder instance
   */
  public static ResponseBuilder success(String action) {
    return new ResponseBuilder(true, action);
  }

  /**
   * @description Creates a new ResponseBuilder initialized for failure.
   * @param action The action key
   * @return A new ResponseBuilder instance
   */
  public static ResponseBuilder error(String action) {
    return new ResponseBuilder(false, action);
  }

  private static List<Object> normalizeDataList(Object dataObj) {
    if (dataObj == null) {
      return new List<Object>();
    }
    if (dataObj instanceof List<Object>) {
      return (List<Object>) dataObj;
    }
    if (dataObj instanceof List<SObject>) {
      List<Object> out = new List<Object>();
      for (SObject record : (List<SObject>) dataObj) {
        out.add(record);
      }
      return out;
    }
    if (dataObj instanceof List<Map<String, Object>>) {
      List<Object> out = new List<Object>();
      for (Map<String, Object> item : (List<Map<String, Object>>) dataObj) {
        out.add(item);
      }
      return out;
    }
    List<Object> wrapped = new List<Object>();
    wrapped.add(dataObj);
    return wrapped;
  }

  private static Integer dataSize(Object dataObj) {
    if (dataObj == null) {
      return 0;
    }
    if (dataObj instanceof List<Object>) {
      return ((List<Object>) dataObj).size();
    }
    if (dataObj instanceof List<SObject>) {
      return ((List<SObject>) dataObj).size();
    }
    if (dataObj instanceof List<Map<String, Object>>) {
      return ((List<Map<String, Object>>) dataObj).size();
    }
    // Handle Map-shaped data envelopes (e.g., SessionService, ReportService)
    if (dataObj instanceof Map<String, Object>) {
      Map<String, Object> dataMap = (Map<String, Object>) dataObj;
      // Check for 'records' list first (most common pattern)
      if (dataMap.containsKey('records') && dataMap.get('records') instanceof List<Object>) {
        return ((List<Object>) dataMap.get('records')).size();
      }
      // Check for 'detailedRows' list
      if (dataMap.containsKey('detailedRows') && dataMap.get('detailedRows') instanceof List<Object>) {
        return ((List<Object>) dataMap.get('detailedRows')).size();
      }
      // If totalCount exists and represents record count, use it
      // Otherwise, treat as single payload object (return 1)
      if (dataMap.containsKey('totalCount')) {
        Object totalCountObj = dataMap.get('totalCount');
        if (totalCountObj instanceof Integer) {
          return (Integer) totalCountObj;
        }
        if (totalCountObj instanceof Decimal) {
          return ((Decimal) totalCountObj).intValue();
        }
        // If totalCount is not numeric, fall through to return 1
      }
      // Single Map payload (not a list of records)
      return 1;
    }
    return 1;
  }

  private static Boolean extractBoolean(Object value) {
    if (value instanceof Boolean) {
      return (Boolean) value;
    }
    if (value == null) {
      return null;
    }
    String text = String.valueOf(value);
    if (String.isBlank(text)) {
      return null;
    }
    if ('true'.equalsIgnoreCase(text)) {
      return true;
    }
    if ('false'.equalsIgnoreCase(text)) {
      return false;
    }
    return null;
  }

  private static String canonicalizeCode(String code, Boolean ok) {
    String resolved = String.isBlank(code)
      ? (ok == null || ok ? AgentCore_Constants.RESULT_CODE_OK : AgentCore_Constants.RESULT_CODE_ERROR)
      : code;
    if (AgentCore_Constants.RESULT_CODE_INVALID_INPUT.equalsIgnoreCase(resolved)) {
      return AgentCore_Constants.RESULT_CODE_INPUT_INVALID;
    }
    if (AgentCore_Constants.RESULT_CODE_VALIDATION_ERROR.equalsIgnoreCase(resolved)) {
      return AgentCore_Constants.RESULT_CODE_INPUT_INVALID;
    }
    return resolved;
  }

  private static List<String> normalizeSuggestions(
    Object rawSuggestions,
    Boolean ok,
    String code
  ) {
    List<String> suggestions = new List<String>();
    if (rawSuggestions instanceof List<Object>) {
      for (Object item : (List<Object>) rawSuggestions) {
        if (item == null) {
          continue;
        }
        String value = String.valueOf(item);
        if (String.isBlank(value)) {
          continue;
        }
        suggestions.add(truncateSuggestion(value));
      }
    } else if (rawSuggestions instanceof List<String>) {
      for (String value : (List<String>) rawSuggestions) {
        if (String.isBlank(value)) {
          continue;
        }
        suggestions.add(truncateSuggestion(value));
      }
    } else if (rawSuggestions != null) {
      String value = String.valueOf(rawSuggestions);
      if (String.isNotBlank(value)) {
        suggestions.add(truncateSuggestion(value));
      }
    }

    if (!ok && suggestions.isEmpty()) {
      suggestions.add(defaultSuggestionForCode(code));
    }

    if (suggestions.size() > MAX_SUGGESTIONS) {
      List<String> trimmed = new List<String>();
      for (Integer i = 0; i < MAX_SUGGESTIONS; i++) {
        trimmed.add(suggestions[i]);
      }
      suggestions = trimmed;
    }
    return suggestions;
  }

  private static List<String> ensureSuggestions(List<String> suggestions, String defaultSuggestion) {
    List<String> safe = new List<String>();
    if (suggestions != null) {
      for (String suggestion : suggestions) {
        if (String.isNotBlank(suggestion)) {
          safe.add(suggestion);
        }
      }
    }
    if (safe.isEmpty()) {
      safe.add(defaultSuggestion);
    }
    return safe;
  }

  private static String defaultSuggestionForCode(String code) {
    if (AgentCore_Constants.RESULT_CODE_PERMISSION_DENIED.equals(code)) {
      return DEFAULT_SUGGESTION_PERMISSION;
    }
    if (AgentCore_Constants.RESULT_CODE_INPUT_INVALID.equals(code)) {
      return DEFAULT_SUGGESTION_GENERIC;
    }
    if (AgentCore_Constants.RESULT_CODE_NOT_FOUND.equals(code)) {
      return DEFAULT_SUGGESTION_NOT_FOUND;
    }
    return DEFAULT_SUGGESTION_GENERIC;
  }

  private static String truncateSuggestion(String value) {
    if (String.isBlank(value) || value.length() <= MAX_SUGGESTION_LENGTH) {
      return value;
    }

    if (value.contains('Date literal format error')) {
      String compactDateLiteral = compactDateLiteralSuggestion(value);
      if (String.isNotBlank(compactDateLiteral)) {
        return compactDateLiteral;
      }
    }

    String fieldRef = extractFieldReference(value);
    String inputClause = extractClause(value, 'You input', '.');
    String expectedClause = extractClause(value, 'Expected format', '.');
    if (String.isBlank(expectedClause)) {
      expectedClause = extractClause(value, 'Expected:', '.');
    }
    String syntaxClause = extractClause(value, 'Here is the correct syntax', '.');
    String resubmitClause = extractClause(value, 'Please resubmit', '.');
    if (String.isBlank(resubmitClause) && value.contains('Please resubmit')) {
      resubmitClause = 'Please resubmit';
    }

    List<String> parts = new List<String>();
    if (String.isNotBlank(fieldRef)) parts.add(fieldRef);
    if (String.isNotBlank(inputClause)) parts.add(inputClause);
    if (String.isNotBlank(expectedClause)) parts.add(expectedClause);
    if (String.isNotBlank(syntaxClause)) parts.add(syntaxClause);
    if (String.isNotBlank(resubmitClause)) parts.add(resubmitClause);

    if (parts.isEmpty()) {
      return value.substring(0, MAX_SUGGESTION_LENGTH - 3) + '...';
    }

    String combined = String.join(parts, ' ');
    if (combined.length() <= MAX_SUGGESTION_LENGTH) {
      return combined;
    }

    String compactField = trimSegment(fieldRef, 30);
    String compactInput = trimSegment(inputClause, 30);
    String compactExpected = trimSegment(expectedClause, 50);
    String compactSyntax = trimSegment(syntaxClause, 40);
    String compactResubmit = String.isNotBlank(resubmitClause) ? 'Please resubmit' : null;

    parts = new List<String>();
    if (String.isNotBlank(compactField)) parts.add(compactField);
    if (String.isNotBlank(compactInput)) parts.add(compactInput);
    if (String.isNotBlank(compactExpected)) parts.add(compactExpected);
    if (String.isNotBlank(compactSyntax)) parts.add(compactSyntax);
    if (String.isNotBlank(compactResubmit)) parts.add(compactResubmit);

    combined = String.join(parts, ' ');
    if (combined.length() <= MAX_SUGGESTION_LENGTH) {
      return combined;
    }

    if (combined.length() > MAX_SUGGESTION_LENGTH) {
      combined = combined.substring(0, MAX_SUGGESTION_LENGTH - 3) + '...';
    }
    return combined;
  }

  private static String compactDateLiteralSuggestion(String value) {
    String literal = extractQuotedValue(value, 'You input');
    String inputClause = null;
    if (String.isNotBlank(literal)) {
      inputClause = 'You input "' + trimSegment(literal, 12) + '".';
    } else {
      inputClause = trimSegment(extractClause(value, 'You input', '.'), 40);
    }

    String fieldRef = extractFieldReference(value);
    String fieldClause = null;
    if (String.isNotBlank(fieldRef)) {
      if (fieldRef.startsWith('field ')) {
        fieldClause = 'Field ' + fieldRef.substring('field '.length()) + '.';
      } else {
        fieldClause = fieldRef + '.';
      }
    }

    String expectedClause = 'Expected format: TODAY, LAST_N_DAYS:X, NEXT_N_DAYS:X.';
    String resubmitClause = 'Please resubmit.';

    List<String> parts = new List<String>();
    if (String.isNotBlank(inputClause)) parts.add(inputClause);
    if (String.isNotBlank(fieldClause)) parts.add(fieldClause);
    parts.add(expectedClause);
    parts.add(resubmitClause);

    String combined = String.join(parts, ' ');
    if (combined.length() <= MAX_SUGGESTION_LENGTH) {
      return combined;
    }

    if (combined.length() > MAX_SUGGESTION_LENGTH) {
      String shorterLiteral = String.isNotBlank(literal) ? trimSegment(literal, 8) : null;
      String trimmedInput = String.isNotBlank(shorterLiteral)
        ? ('You input "' + shorterLiteral + '".')
        : trimSegment(inputClause, 30);
      parts = new List<String>();
      if (String.isNotBlank(trimmedInput)) parts.add(trimmedInput);
      if (String.isNotBlank(fieldClause)) parts.add(fieldClause);
      parts.add(expectedClause);
      parts.add(resubmitClause);
      combined = String.join(parts, ' ');
      if (combined.length() <= MAX_SUGGESTION_LENGTH) {
        return combined;
      }
    }

    return trimSegment(combined, MAX_SUGGESTION_LENGTH);
  }

  private static String extractFieldReference(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    if (value.contains('Text validation error')) {
      return 'Text validation error';
    }
    Integer fieldIdx = value.indexOf('field "');
    if (fieldIdx >= 0) {
      Integer start = fieldIdx + 'field "'.length();
      Integer endIdx = value.indexOf('"', start);
      if (endIdx > start) {
        return 'field "' + value.substring(start, endIdx) + '"';
      }
    }
    Integer singleIdx = value.indexOf('field \'');
    if (singleIdx >= 0) {
      Integer start = singleIdx + 'field \''.length();
      Integer endIdx = value.indexOf('\'', start);
      if (endIdx > start) {
        return 'field "' + value.substring(start, endIdx) + '"';
      }
    }
    return null;
  }

  private static String extractQuotedValue(String value, String token) {
    if (String.isBlank(value) || String.isBlank(token)) {
      return null;
    }
    Integer tokenIdx = value.indexOf(token);
    if (tokenIdx < 0) {
      return null;
    }
    Integer firstQuote = value.indexOf('"', tokenIdx);
    if (firstQuote < 0) {
      return null;
    }
    Integer secondQuote = value.indexOf('"', firstQuote + 1);
    if (secondQuote <= firstQuote) {
      return null;
    }
    return value.substring(firstQuote + 1, secondQuote);
  }

  private static String extractClause(String value, String token, String terminator) {
    if (String.isBlank(value) || String.isBlank(token)) {
      return null;
    }
    Integer start = value.indexOf(token);
    if (start < 0) {
      return null;
    }
    Integer endIdx = -1;
    if (terminator != null) {
      endIdx = value.indexOf(terminator, start);
    }
    if (endIdx < 0) {
      endIdx = Math.min(value.length(), start + MAX_SUGGESTION_LENGTH);
      return value.substring(start, endIdx).trim();
    }
    return value.substring(start, Math.min(value.length(), endIdx + terminator.length())).trim();
  }

  private static String trimSegment(String segment, Integer maxLen) {
    if (String.isBlank(segment) || maxLen == null || maxLen <= 0) {
      return null;
    }
    if (segment.length() <= maxLen) {
      return segment;
    }
    if (maxLen <= 3) {
      return segment.substring(0, maxLen);
    }
    return segment.substring(0, maxLen - 3) + '...';
  }

  private static Map<String, Object> normalizePermissions(
    Object permissionsObj,
    String action,
    String code
  ) {
    Map<String, Object> permissions = permissionsObj instanceof Map<String, Object>
      ? (Map<String, Object>) permissionsObj
      : new Map<String, Object>();

    Boolean allowed = extractBoolean(permissions.get('allowed'));
    if (AgentCore_Constants.RESULT_CODE_PERMISSION_DENIED.equals(code)) {
      allowed = false;
    }
    if (allowed == null) {
      allowed = true;
    }
    permissions.put('allowed', allowed);
    Boolean evaluated = extractBoolean(permissions.get('evaluated'));
    if (evaluated == null) {
      evaluated = AgentCore_Constants.RESULT_CODE_PERMISSION_DENIED.equals(code);
    }
    permissions.put('evaluated', evaluated);
    permissions.put('permissionDenied', !allowed);

    Object actionEvalObj = permissions.get('actionEvaluation');
    Map<String, Object> actionEvaluation = null;
    if (actionEvalObj instanceof Map<String, Object>) {
      actionEvaluation = new Map<String, Object>((Map<String, Object>) actionEvalObj);
    } else if (actionEvalObj instanceof AgentCore_PermissionValidator.ActionEvaluation) {
      actionEvaluation = ((AgentCore_PermissionValidator.ActionEvaluation) actionEvalObj).toMap();
    }
    if (actionEvaluation == null) {
      actionEvaluation = new Map<String, Object>();
    }
    if (!actionEvaluation.containsKey('actionKey')) {
      actionEvaluation.put('actionKey', String.isBlank(action) ? DEFAULT_ACTION : action);
    }
    if (!actionEvaluation.containsKey('allowed')) {
      actionEvaluation.put('allowed', allowed);
    }
    if (!actionEvaluation.containsKey('requiredCustomPermissions')) {
      actionEvaluation.put('requiredCustomPermissions', new List<String>());
    }
    if (!actionEvaluation.containsKey('missingCustomPermissions')) {
      actionEvaluation.put('missingCustomPermissions', new List<String>());
    }
    if (!actionEvaluation.containsKey('message')) {
      actionEvaluation.put('message', '');
    }
    if (!actionEvaluation.containsKey('suggestions')) {
      actionEvaluation.put('suggestions', new List<String>());
    }
    permissions.put('actionEvaluation', actionEvaluation);
    return permissions;
  }

  private static String buildHeader(
    Boolean ok,
    String code,
    String summary,
    String error,
    List<String> suggestions,
    Map<String, Object> meta
  ) {
    String header;
    if (ok) {
      Integer recordCount = extractInteger(meta != null ? meta.get('recordCount') : null);
      String suffix = '';
      if (recordCount != null && recordCount > 0) {
        suffix =
          ' Returned ' +
          String.valueOf(recordCount) +
          (recordCount == 1 ? ' record.' : ' records.');
      }
      header = 'OK: ' + summary + suffix;
    } else {
      String err = String.isBlank(error) ? summary : error;
      String next = (suggestions != null && !suggestions.isEmpty())
        ? ' Next: ' + suggestions[0]
        : '';
      header = String.valueOf(code) + ': ' + err + '.' + next;
    }
    return truncateHeader(header);
  }

  private static String truncateHeader(String header) {
    if (String.isBlank(header)) {
      return '';
    }
    Integer maxLen = AgentCore_Constants.AI_HEADER_MAX_LENGTH;
    if (header.length() <= maxLen) {
      return header;
    }
    return header.substring(0, maxLen - 3) + '...';
  }

  private static Integer extractInteger(Object value) {
    if (value == null) {
      return null;
    }
    try {
      if (value instanceof Integer) {
        return (Integer) value;
      }
      if (value instanceof Long) {
        return Integer.valueOf(String.valueOf(value));
      }
      if (value instanceof Decimal) {
        return ((Decimal) value).intValue();
      }
      String text = String.valueOf(value);
      if (String.isBlank(text)) {
        return null;
      }
      return Integer.valueOf(text);
    } catch (Exception e) {
      return null;
    }
  }

  private static void writeField(
    JSONGenerator gen,
    String field,
    Object value,
    Boolean required
  ) {
    if (gen == null || String.isBlank(field)) {
      return;
    }

    if (!required) {
      if (value == null) {
        return;
      }
      if (value instanceof List<Object> && ((List<Object>) value).isEmpty()) {
        return;
      }
      if (value instanceof List<String> && ((List<String>) value).isEmpty()) {
        return;
      }
    }

    gen.writeFieldName(field);
    if (value == null) {
      gen.writeNull();
    } else {
      gen.writeObject(value);
    }
  }
}