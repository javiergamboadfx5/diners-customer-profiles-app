#!/usr/bin/env bash
# verify-saml.sh
#
# Post-apply, read-only verification of the SAML federation stack of the dev
# Connect build (Requirements 14.3 and 14.4). Issues only read calls:
#   ssm describe-parameters / get-parameter, connect describe-instance,
#   iam get-saml-provider / get-role / list-attached-role-policies /
#   list-role-policies / get-policy / get-policy-version.
#
# The sign-in test itself (IdP-initiated sign-in with a UPN test user and the
# refused unassigned user) is manual. Record it with
# saml-signin-record-template.md next to this script.
#
# Writes one JSON evidence line per check (check, expected, actual, result,
# timestamp) to stdout, and also appends them to EVIDENCE_FILE when it is set.
# Exits 0 when every check passes, 1 when any check fails, 2 on usage errors.
#
# Required environment:
#   WORKLOAD            Catalog workload code (OQ-1). No default.
#   SAML_RESOURCE_CODE  Catalog resource code used in the SAML provider names
#                       (OQ-3, proposed `saml`). No default.
# Optional environment:
#   AWS_REGION          Default us-east-1.
#   AWS_PROFILE         Standard AWS CLI profile selection.
#   EVIDENCE_FILE       File to append the JSON evidence lines to.
#
# Example:
#   WORKLOAD=<workload> SAML_RESOURCE_CODE=<code> \
#     EVIDENCE_FILE=evidence/verify-saml.jsonl bash verify-saml.sh
set -u -o pipefail
usage_error() {
  echo "verify-saml: $*" >&2
  exit 2
}
for tool in aws jq; do
  command -v "$tool" >/dev/null 2>&1 || usage_error "required tool not found in PATH: $tool"
done
WORKLOAD="${WORKLOAD:-}"
[[ "$WORKLOAD" =~ ^[a-z0-9-]+$ ]] || usage_error "WORKLOAD must be set to the catalog workload code (OQ-1)"
SAML_RESOURCE_CODE="${SAML_RESOURCE_CODE:-}"
[[ "$SAML_RESOURCE_CODE" =~ ^[a-z0-9-]+$ ]] || usage_error "SAML_RESOURCE_CODE must be set to the catalog resource code (OQ-3)"
REGION="${AWS_REGION:-us-east-1}"
EVIDENCE_FILE="${EVIDENCE_FILE:-}"
DOMAIN="diners"
ENVIRONMENT="dev"
SSM_PREFIX="/dcp/${DOMAIN}/${ENVIRONMENT}/${WORKLOAD}/config"
ROLE_PREFIX="dcp-${DOMAIN}-${ENVIRONMENT}-${WORKLOAD}"
ROLE_NAME="${ROLE_PREFIX}-role-connect-federation"
POLICY_NAME="${ROLE_PREFIX}-policy-connect-federation"
PROVIDER_ADMIN_NAME="${ROLE_PREFIX}-${SAML_RESOURCE_CODE}-admin"
PROVIDER_AGENT_NAME="${ROLE_PREFIX}-${SAML_RESOURCE_CODE}-agent"
BOUNDARY_NAME="dcp-platform-permission-boundary"
EXPECTED_AUDIENCE="https://signin.aws.amazon.com/saml"
EXPECTED_TRUST_ACTION="sts:AssumeRoleWithSAML"
EXPECTED_POLICY_ACTION="connect:GetFederationToken"
EXPECTED_IDENTITY_TYPE="SAML"
MAX_SESSION_LIMIT=3600
FAILURES=0
RESULT_JSON=""
ERR_MSG=""
INSTANCE_ARN=""
ACCOUNT_ID=""
INSTANCE_ID=""
# jq helper for array-or-object fields in IAM documents.
read -r -d '' JQ_LIB <<'JQ' || true
def arr: if type == "array" then . else [.] end;
JQ
now_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}
# emit <check> <expected> <actual> <result>
emit() {
  local line
  line=$(jq -cn --arg check "$1" --arg expected "$2" --arg actual "$3" \
    --arg result "$4" --arg timestamp "$(now_utc)" \
    '{check: $check, expected: $expected, actual: $actual, result: $result, timestamp: $timestamp}')
  printf '%s\n' "$line"
  if [[ -n "$EVIDENCE_FILE" ]]; then
    printf '%s\n' "$line" >> "$EVIDENCE_FILE"
  fi
  if [[ "$4" != "pass" ]]; then
    FAILURES=$((FAILURES + 1))
  fi
}
# check_eq <check> <expected> <actual>: pass only when actual equals expected.
check_eq() {
  local check="$1" expected="$2" actual="$3"
  if [[ -z "$actual" ]]; then
    actual="not evaluated: empty value"
  fi
  if [[ "$actual" == "$expected" ]]; then
    emit "$check" "$expected" "$actual" pass
  else
    emit "$check" "$expected" "$actual" fail
  fi
}
# aws_read <aws arguments...>: read-only CLI call. Sets RESULT_JSON on success,
# or ERR_MSG (first stderr line) on failure.
aws_read() {
  local out errfile
  errfile=$(mktemp)
  if out=$(aws "$@" --region "$REGION" --output json 2>"$errfile"); then
    RESULT_JSON="$out"
    ERR_MSG=""
    rm -f "$errfile"
    return 0
  fi
  RESULT_JSON=""
  ERR_MSG=$(head -n 1 "$errfile")
  rm -f "$errfile"
  return 1
}
# value_of <json> <error> <jq filter>: prints the extracted value, or the error text.
value_of() {
  if [[ -z "$1" ]]; then
    printf 'error: %s' "$2"
    return
  fi
  jq -r "$3" <<<"$1" 2>/dev/null || printf 'error: unparsable response'
}
# load_ssm <parameter short name> <target variable>: reads a contract under SSM_PREFIX.
load_ssm() {
  local short="$1" target="$2" name value=""
  name="${SSM_PREFIX}/${short}"
  if aws_read ssm get-parameter --name "$name"; then
    value=$(jq -r '.Parameter.Value // ""' <<<"$RESULT_JSON")
  fi
  if [[ -n "$value" ]]; then
    emit "ssm:${short}" "present" "present" pass
  else
    emit "ssm:${short}" "present" "missing: ${ERR_MSG:-empty value}" fail
  fi
  printf -v "$target" '%s' "$value"
}
# ssm_metadata_present <parameter short name>: checks existence only, never reads the value.
ssm_metadata_present() {
  local short="$1" name count=""
  name="${SSM_PREFIX}/${short}"
  if aws_read ssm describe-parameters --parameter-filters "Key=Name,Option=Equals,Values=${name}"; then
    count=$(jq -r '(.Parameters // []) | length' <<<"$RESULT_JSON")
  fi
  if [[ "$count" == "1" ]]; then
    emit "ssm:${short}" "present" "present" pass
  else
    emit "ssm:${short}" "present" "missing: ${ERR_MSG:-no parameter named ${name}}" fail
  fi
}
# check_provider <check> <provider ARN>: the SAML provider must exist.
check_provider() {
  local check="$1" arn="$2"
  if [[ -z "$arn" ]]; then
    emit "$check" "present" "not evaluated: account not available from SSM" fail
    return
  fi
  if aws_read iam get-saml-provider --saml-provider-arn "$arn"; then
    emit "$check" "present" "present" pass
  else
    emit "$check" "present" "missing: ${ERR_MSG:-no provider}" fail
  fi
}
# --- 1. Contracts from SSM -------------------------------------------------
load_ssm connect-instance-arn INSTANCE_ARN
# The instance ARN is arn:aws:connect:<region>:<account>:instance/<uuid>.
if [[ "$INSTANCE_ARN" =~ ^arn:aws:connect:[a-z0-9-]+:([0-9]{12}):instance/([0-9a-f-]+)$ ]]; then
  ACCOUNT_ID="${BASH_REMATCH[1]}"
  INSTANCE_ID="${BASH_REMATCH[2]}"
  emit "ssm:connect-instance-arn.format" "valid instance ARN" "valid instance ARN" pass
else
  emit "ssm:connect-instance-arn.format" "valid instance ARN" \
    "${INSTANCE_ARN:+invalid: }${INSTANCE_ARN:-not evaluated: empty value}" fail
fi
# Both metadata contracts must exist (Requirement 10.4). Values are not read.
ssm_metadata_present saml-metadata-admin
ssm_metadata_present saml-metadata-agent
# --- 2. Identity type (Requirements 10.5, 14.3) ----------------------------
IDENTITY_TYPE=""
IDENTITY_ERR="not evaluated: instance ID not available from SSM"
if [[ -n "$INSTANCE_ID" ]]; then
  if aws_read connect describe-instance --instance-id "$INSTANCE_ID"; then
    IDENTITY_TYPE=$(value_of "$RESULT_JSON" "" '.Instance.IdentityManagementType // ""')
  else
    IDENTITY_ERR="error: $ERR_MSG"
  fi
fi
check_eq "connect.identity-management-type" "$EXPECTED_IDENTITY_TYPE" \
  "${IDENTITY_TYPE:-$IDENTITY_ERR}"
# --- 3. SAML providers (Requirement 10.1) ----------------------------------
PROVIDER_ADMIN_ARN=""
PROVIDER_AGENT_ARN=""
if [[ -n "$ACCOUNT_ID" ]]; then
  PROVIDER_ADMIN_ARN="arn:aws:iam::${ACCOUNT_ID}:saml-provider/${PROVIDER_ADMIN_NAME}"
  PROVIDER_AGENT_ARN="arn:aws:iam::${ACCOUNT_ID}:saml-provider/${PROVIDER_AGENT_NAME}"
fi
check_provider "iam.saml-provider.admin" "$PROVIDER_ADMIN_ARN"
check_provider "iam.saml-provider.agent" "$PROVIDER_AGENT_ARN"
# --- 4. Federation role (Requirements 10.1, 10.3) --------------------------
ROLE_JSON=""
ROLE_ERR=""
if aws_read iam get-role --role-name "$ROLE_NAME"; then
  ROLE_JSON="$RESULT_JSON"
else
  ROLE_ERR="error: $ERR_MSG"
fi
check_eq "iam.federation-role.name" "$ROLE_NAME" \
  "$(value_of "$ROLE_JSON" "$ROLE_ERR" '.Role.RoleName // ""')"
# Trust: one Allow statement for sts:AssumeRoleWithSAML, both providers as
# Federated principals, and the StringEquals SAML:aud condition only.
TRUST_EXPECTED="not evaluated: provider ARNs not available from SSM"
if [[ -n "$ACCOUNT_ID" ]]; then
  TRUST_EXPECTED=$(jq -rn --arg a1 "$PROVIDER_ADMIN_ARN" --arg a2 "$PROVIDER_AGENT_ARN" \
    --arg act "$EXPECTED_TRUST_ACTION" --arg aud "$EXPECTED_AUDIENCE" \
    '"statements=1 effect=Allow actions=\($act) federated=\([$a1, $a2] | sort | join(",")) condition_ops=StringEquals saml_aud=\($aud)"')
fi
TRUST_ACTUAL=$(value_of "$ROLE_JSON" "$ROLE_ERR" "${JQ_LIB}
(.Role.AssumeRolePolicyDocument.Statement | arr) as \$s
| \"statements=\(\$s | length) effect=\(\$s[0].Effect // \"\") actions=\(\$s[0].Action | arr | join(\",\")) federated=\(\$s[0].Principal.Federated | arr | sort | join(\",\")) condition_ops=\((\$s[0].Condition // {}) | keys | join(\",\")) saml_aud=\(\$s[0].Condition.StringEquals[\"SAML:aud\"] // \"\")\"")
check_eq "iam.federation-role.trust" "$TRUST_EXPECTED" "$TRUST_ACTUAL"
# Permission boundary (Requirement 10.3).
BOUNDARY_EXPECTED="not evaluated: account not available from SSM"
if [[ -n "$ACCOUNT_ID" ]]; then
  BOUNDARY_EXPECTED="arn:aws:iam::${ACCOUNT_ID}:policy/${BOUNDARY_NAME}"
fi
check_eq "iam.federation-role.permission-boundary" "$BOUNDARY_EXPECTED" \
  "$(value_of "$ROLE_JSON" "$ROLE_ERR" '.Role.PermissionsBoundary.PermissionsBoundaryArn // ""')"
# Maximum session duration must be an integer no greater than 3600 (Requirement 10.3).
MAX_SESSION=$(value_of "$ROLE_JSON" "$ROLE_ERR" '(.Role.MaxSessionDuration // "") | tostring')
if [[ "$MAX_SESSION" =~ ^[0-9]+$ ]] && ((MAX_SESSION <= MAX_SESSION_LIMIT)); then
  emit "iam.federation-role.max-session-duration" "<= ${MAX_SESSION_LIMIT}" "$MAX_SESSION" pass
else
  emit "iam.federation-role.max-session-duration" "<= ${MAX_SESSION_LIMIT}" \
    "${MAX_SESSION:-not evaluated: empty value}" fail
fi
# --- 5. Single policy (Requirement 10.2) -----------------------------------
ATTACHED_JSON=""
ATTACHED_ERR="not evaluated: role not readable"
if [[ -n "$ROLE_JSON" ]]; then
  if aws_read iam list-attached-role-policies --role-name "$ROLE_NAME"; then
    ATTACHED_JSON="$RESULT_JSON"
  else
    ATTACHED_ERR="error: $ERR_MSG"
  fi
fi
check_eq "iam.federation-role.attached-policies" "$POLICY_NAME" \
  "$(value_of "$ATTACHED_JSON" "$ATTACHED_ERR" '[.AttachedPolicies[]? | .PolicyName] | join(",")')"
INLINE_ERR="not evaluated: role not readable"
INLINE_NAMES=""
if [[ -n "$ROLE_JSON" ]]; then
  if aws_read iam list-role-policies --role-name "$ROLE_NAME"; then
    INLINE_NAMES=$(jq -r '[.PolicyNames[]?] | if length == 0 then "none" else join(",") end' <<<"$RESULT_JSON")
  else
    INLINE_ERR="error: $ERR_MSG"
  fi
fi
check_eq "iam.federation-role.inline-policies" "none" "${INLINE_NAMES:-$INLINE_ERR}"
POLICY_ARN=""
if [[ -n "$ATTACHED_JSON" ]]; then
  POLICY_ARN=$(jq -r --arg n "$POLICY_NAME" \
    '[.AttachedPolicies[]? | select(.PolicyName == $n) | .PolicyArn] | .[0] // ""' <<<"$ATTACHED_JSON" 2>/dev/null)
fi
# Policy document: one Allow statement, connect:GetFederationToken, instance/<id>/user/* only.
POLICY_EXPECTED="not evaluated: instance ARN not available from SSM"
if [[ -n "$INSTANCE_ARN" ]]; then
  POLICY_EXPECTED="statements=1 effect=Allow actions=${EXPECTED_POLICY_ACTION} resources=${INSTANCE_ARN}/user/* extra="
fi
POLICY_ACTUAL="not evaluated: policy not attached to role"
if [[ -n "$POLICY_ARN" ]]; then
  if aws_read iam get-policy --policy-arn "$POLICY_ARN"; then
    VERSION_ID=$(jq -r '.Policy.DefaultVersionId // ""' <<<"$RESULT_JSON")
    if aws_read iam get-policy-version --policy-arn "$POLICY_ARN" --version-id "$VERSION_ID"; then
      POLICY_ACTUAL=$(jq -r "${JQ_LIB}
(.PolicyVersion.Document.Statement | arr) as \$s
| \"statements=\(\$s | length) effect=\(\$s[0].Effect // \"\") actions=\(\$s[0].Action | arr | join(\",\")) resources=\(\$s[0].Resource | arr | join(\",\")) extra=\([\$s[0] | keys[] | select(. as \$k | [\"Sid\",\"Effect\",\"Action\",\"Resource\"] | index(\$k) | not)] | join(\",\"))\"" <<<"$RESULT_JSON" 2>/dev/null) ||
        POLICY_ACTUAL="error: unparsable policy document"
    else
      POLICY_ACTUAL="error: $ERR_MSG"
    fi
  else
    POLICY_ACTUAL="error: $ERR_MSG"
  fi
fi
check_eq "iam.federation-policy.statement" "$POLICY_EXPECTED" "$POLICY_ACTUAL"
if [[ "$FAILURES" -gt 0 ]]; then
  exit 1
fi
exit 0
