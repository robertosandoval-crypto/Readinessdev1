/**
 * @description Constants used across the AgentCore framework for standardized
 * response envelopes, result codes, and AI-friendly field names.
 */
public with sharing class AgentCore_Constants {
  // ── Response envelope field names ──
  public static final String AI_FIELD_OK = 'ok';
  public static final String AI_FIELD_ACTION = 'action';
  public static final String AI_FIELD_DATA = 'data';
  public static final String AI_FIELD_META = 'meta';
  public static final String AI_FIELD_ERROR = 'error';
  public static final String AI_FIELD_SUGGESTIONS = 'suggestions';
  public static final String AI_FIELD_SCHEMA = 'schema';
  public static final String AI_FIELD_PERMISSIONS = 'permissions';
  public static final String AI_FIELD_SUMMARY = 'summary';
  public static final String AI_FIELD_HEADER = 'header';
  public static final String AI_FIELD_NEXT = 'next';

  // ── Result codes ──
  public static final String RESULT_CODE_OK = 'OK';
  public static final String RESULT_CODE_ERROR = 'ERROR';
  public static final String RESULT_CODE_INPUT_INVALID = 'INPUT_INVALID';
  public static final String RESULT_CODE_NOT_FOUND = 'NOT_FOUND';
  public static final String RESULT_CODE_PERMISSION_DENIED = 'PERMISSION_DENIED';
  public static final String RESULT_CODE_TOO_LARGE = 'TOO_LARGE';
  public static final String RESULT_CODE_PARTIAL_SUCCESS = 'PARTIAL_SUCCESS';

  // ── Aliases (canonical forms mapped in AgentCore_Response.canonicalizeCode) ──
  public static final String RESULT_CODE_INVALID_INPUT = 'INVALID_INPUT';
  public static final String RESULT_CODE_VALIDATION_ERROR = 'VALIDATION_ERROR';

  // ── Header constraints ──
  public static final Integer AI_HEADER_MAX_LENGTH = 500;
}
