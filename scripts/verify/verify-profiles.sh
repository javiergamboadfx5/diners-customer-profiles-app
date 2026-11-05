#!/usr/bin/env bash
# verify-profiles.sh
#
# Post-apply, read-only verification of the Customer Profiles stacks of the dev
# Connect build (Requirements 14.2 and 14.4). Issues only read calls:
#   ssm get-parameter, customer-profiles get-domain / get-profile-object-type /
#   list-integrations, kms get-key-policy / get-key-rotation-status.
#
# Writes one JSON evidence line per check (check, expected, actual, result,
# timestamp) to stdout, and also appends them to EVIDENCE_FILE when it is set.
# Exits 0 when every check passes, 1 when any check fails, 2 on usage errors.
#
# Required environment:
#   WORKLOAD                          Catalog workload code (OQ-1). No default.
#   EXPECTED_DEFAULT_EXPIRATION_DAYS  Approved domain expiration (OQ-10). No default.
# Optional environment:
#   EXPECTED_DATA_STORE_ENABLED       true or false. Default false (Requirement 8.3).
#   AWS_REGION                        Default us-east-1.
#   AWS_PROFILE                       Standard AWS CLI profile selection.
#   EVIDENCE_FILE                     File to append the JSON evidence lines to.
#
# Example:
#   WORKLOAD=<workload> EXPECTED_DEFAULT_EXPIRATION_DAYS=<days> \
#     EVIDENCE_FILE=evidence/verify-profiles.jsonl bash verify-profiles.sh

set -u -o pipefail

usage_error() {
  echo "verify-profiles: $*" >&2
  exit 2
}

for tool in aws jq; do
  command -v "$tool" >/dev/null 2>&1 || usage_error "required tool not found in PATH: $tool"
done

WORKLOAD="${WORKLOAD:-}"
[[ "$WORKLOAD" =~ ^[a-z0-9-]+$ ]] || usage_error "WORKLOAD must be set to the catalog workload code (OQ-1)"

EXPECTED_EXPIRATION="${EXPECTED_DEFAULT_EXPIRATION_DAYS:-}"
[[ "$EXPECTED_EXPIRATION" =~ ^[0-9]+$ ]] || usage_error "EXPECTED_DEFAULT_EXPIRATION_DAYS must be the approved integer (OQ-10)"

EXPECTED_DATA_STORE="${EXPECTED_DATA_STORE_ENABLED:-false}"
case "$EXPECTED_DATA_STORE" in
  true | false) ;;
  *) usage_error "EXPECTED_DATA_STORE_ENABLED must be true or false" ;;
esac

REGION="${AWS_REGION:-us-east-1}"
SSM_PREFIX="/dcp/diners/dev/${WORKLOAD}/config"
EXPECTED_DOMAIN_NAME="amazon-connect-dcp-diners-dev-${WORKLOAD}"
EXPECTED_OBJECT_TYPE="CTR"
EXPECTED_TEMPLATE="CTR-AutoAssociateOnly"
EVIDENCE_FILE="${EVIDENCE_FILE:-}"

FAILURES=0
RESULT_JSON=""
ERR_MSG=""
DOMAIN_NAME=""
DOMAIN_ARN=""
KEY_ARN=""
INSTANCE_ARN=""
POLICY_JSON=""
POLICY_ERR=""

# jq library for the key policy checks (Requirement 7.2).
read -r -d '' JQ_LIB <<'JQ' || true
def arr: if type == "array" then . else [.] end;
def stmts: .Statement | arr;
def allow: .Effect == "Allow";
def principal_of($k): (.Principal | if type == "object" then (.[$k] // []) else [] end) | arr;
def svc: principal_of("Service");
def aws_principals: principal_of("AWS");
def has_svc($n): svc | any(. == $n);
def actions: (.Action // []) | arr;
def has_all($list): . as $s | all($list[]; . as $x | $s | actions | any(. == $x or . == ($x | rtrimstr("*"))));
def cond_keys: [(.Condition // {}) | .. | objects | keys[]];
def cond_values: [(.Condition // {}) | .. | strings];
def has_key($k): cond_keys | any(. == $k);
def has_value($v): cond_values | any(. == $v);
def is_in($set): . as $a | any($set[]; . == $a);
def admin_actions: ["kms:Create*","kms:Put*","kms:Describe*","kms:Enable*","kms:Disable*","kms:Update*","kms:Tag*","kms:Untag*","kms:ScheduleKeyDeletion","kms:CancelKeyDeletion"];
def usage_actions: ["kms:Encrypt","kms:Decrypt","kms:ReEncrypt*","kms:GenerateDataKey*","kms:GenerateDataKey","kms:GenerateDataKeyWithoutPlaintext","kms:*"];
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

# load_ssm <parameter short name> <target variable>: reads the contract under SSM_PREFIX.
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

# policy_check <check> <jq boolean expression>: evaluates against the parsed key policy.
policy_check() {
  local check="$1" expr="$2" value
  if [[ -z "$POLICY_JSON" ]]; then
    check_eq "$check" "true" "$POLICY_ERR"
    return
  fi
  value=$(jq -r --arg arn "$DOMAIN_ARN" "${JQ_LIB}
${expr}" <<<"$POLICY_JSON" 2>/dev/null) || value="error: policy evaluation failed"
  check_eq "$check" "true" "$value"
}

# --- 1. Contracts from SSM -------------------------------------------------
load_ssm customer-profiles-domain-name DOMAIN_NAME
load_ssm customer-profiles-domain-arn DOMAIN_ARN
load_ssm customer-profiles-kms-key-arn KEY_ARN
load_ssm connect-instance-arn INSTANCE_ARN

check_eq "ssm:customer-profiles-domain-name.value" "$EXPECTED_DOMAIN_NAME" "$DOMAIN_NAME"

# --- 2. Domain: key, expiration, data store (Requirement 14.2) -------------
DOMAIN_JSON=""
DOMAIN_ERR="not evaluated: domain name not available from SSM"
if [[ -n "$DOMAIN_NAME" ]]; then
  if aws_read customer-profiles get-domain --domain-name "$DOMAIN_NAME"; then
    DOMAIN_JSON="$RESULT_JSON"
    DOMAIN_ERR=""
  else
    DOMAIN_ERR="$ERR_MSG"
  fi
fi

check_eq "customer-profiles.domain-key" \
  "${KEY_ARN:-missing SSM input: customer-profiles-kms-key-arn}" \
  "$(value_of "$DOMAIN_JSON" "$DOMAIN_ERR" '.DefaultEncryptionKey // ""')"

check_eq "customer-profiles.default-expiration-days" \
  "$EXPECTED_EXPIRATION" \
  "$(value_of "$DOMAIN_JSON" "$DOMAIN_ERR" '(.DefaultExpirationDays // "") | tostring')"

check_eq "customer-profiles.data-store-enabled" \
  "$EXPECTED_DATA_STORE" \
  "$(value_of "$DOMAIN_JSON" "$DOMAIN_ERR" 'if (.DataStore.Enabled // false) then "true" else "false" end')"

# --- 3. CTR object type and integration (Requirement 14.2) -----------------
CTR_TEMPLATE=""
CTR_ERR="not evaluated: domain name not available from SSM"
if [[ -n "$DOMAIN_NAME" ]]; then
  if aws_read customer-profiles get-profile-object-type --domain-name "$DOMAIN_NAME" \
    --object-type-name "$EXPECTED_OBJECT_TYPE"; then
    CTR_TEMPLATE=$(value_of "$RESULT_JSON" "" '.TemplateId // ""')
  else
    CTR_ERR="$ERR_MSG"
  fi
fi
check_eq "customer-profiles.ctr-object-type-template" \
  "$EXPECTED_TEMPLATE" \
  "${CTR_TEMPLATE:-$CTR_ERR}"

INTEGRATIONS=""
INTEGRATIONS_ERR="not evaluated: domain name not available from SSM"
if [[ -n "$DOMAIN_NAME" ]]; then
  if aws_read customer-profiles list-integrations --domain-name "$DOMAIN_NAME"; then
    INTEGRATIONS=$(jq -c '[(.Items // [])[] | {uri: .Uri, object_type: .ObjectTypeName}]' <<<"$RESULT_JSON" 2>/dev/null)
  else
    INTEGRATIONS_ERR="$ERR_MSG"
  fi
fi
check_eq "customer-profiles.integrations" \
  "$(jq -cn --arg u "${INSTANCE_ARN:-missing SSM input: connect-instance-arn}" \
    --arg t "$EXPECTED_OBJECT_TYPE" '[{uri: $u, object_type: $t}]')" \
  "${INTEGRATIONS:-$INTEGRATIONS_ERR}"

# --- 4. Key policy (Requirement 7.2) ---------------------------------------
if [[ -n "$KEY_ARN" ]]; then
  if aws_read kms get-key-policy --key-id "$KEY_ARN" --policy-name default; then
    POLICY_JSON=$(jq -c '.Policy | fromjson' <<<"$RESULT_JSON" 2>/dev/null) || POLICY_JSON=""
    [[ -n "$POLICY_JSON" ]] || POLICY_ERR="error: unparsable key policy"
  else
    POLICY_ERR="error: $ERR_MSG"
  fi
else
  POLICY_ERR="not evaluated: key ARN not available from SSM"
fi

policy_check "kms.key-policy.profile-service" \
  'any(stmts[]; allow and has_svc("profile.amazonaws.com") and has_all(["kms:Encrypt","kms:Decrypt","kms:GenerateDataKey*","kms:DescribeKey","kms:CreateGrant"]) and has_key("aws:SourceAccount") and has_value($arn))'

policy_check "kms.key-policy.connect-service" \
  'any(stmts[]; allow and has_svc("connect.amazonaws.com") and has_all(["kms:Decrypt"]) and has_key("aws:SourceAccount"))'

policy_check "kms.key-policy.key-admin" \
  'any(stmts[]; allow and (aws_principals | length > 0) and (aws_principals | any(. != "*")) and (actions | any(is_in(admin_actions))) and ((actions | any(is_in(usage_actions))) | not))'

policy_check "kms.key-policy.terraform-apply-role" \
  'any(stmts[]; allow and (aws_principals | any(contains("TerraformApplyRole"))) and has_all(["kms:CreateGrant","kms:DescribeKey"]))'

policy_check "kms.key-policy.no-unconditioned-principal-star" \
  '[stmts[] | select(allow) | select((.Principal == "*") or (aws_principals | any(. == "*"))) | select((.Condition // {}) == {})] | length == 0'

# --- 5. Key rotation (Requirement 7.1) -------------------------------------
ROTATION=""
ROTATION_ERR="not evaluated: key ARN not available from SSM"
if [[ -n "$KEY_ARN" ]]; then
  if aws_read kms get-key-rotation-status --key-id "$KEY_ARN"; then
    ROTATION=$(value_of "$RESULT_JSON" "" '(.KeyRotationEnabled // false) | tostring')
  else
    ROTATION_ERR="error: $ERR_MSG"
  fi
fi
check_eq "kms.key-rotation-enabled" "true" "${ROTATION:-$ROTATION_ERR}"

if [[ "$FAILURES" -gt 0 ]]; then
  exit 1
fi
exit 0
