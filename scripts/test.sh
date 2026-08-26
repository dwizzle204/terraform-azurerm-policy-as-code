#!/usr/bin/env bash
# Credential-free validation gate for terraform-azurerm-policy-as-code (issue #16)
# Layers: fmt -> per-module init/validate/test -> examples validate -> missing-definition negative check.
# Requires no Azure tenant or credentials. Terraform >= 1.7 (mock_provider) required.
set -euo pipefail

TF="${TF_BIN:-terraform}"
TFLINT="${TFLINT_BIN:-tflint}"
TMPDIR_INIT_LOG=$(mktemp)
MODULES=(definition initiative exemption def_assignment set_assignment)
FAILED=()

command -v "$TF" >/dev/null || { echo "terraform not found"; exit 1; }
command -v "$TFLINT" >/dev/null || { echo "tflint not found - required for a successful build. Install: https://github.com/terraform-linters/tflint#installation"; exit 1; }

echo "== terraform fmt -check -recursive =="
if ! "$TF" fmt -check -recursive .; then FAILED+=("fmt"); fi

echo "== provider constraint consistency (#9) =="
RV_EXPECT='required_version = ">= 1.11"'
AZ_EXPECT='version = ">= 4.35, < 6.0"'
for m in "${MODULES[@]}"; do
  grep -qF "$RV_EXPECT" "modules/$m/versions.tf" || { echo "constraint drift in modules/$m/versions.tf: missing '$RV_EXPECT'"; diff <(echo "$RV_EXPECT") <(grep required_version "modules/$m/versions.tf"); FAILED+=("constraints:$m"); }
  grep -qF "$AZ_EXPECT" "modules/$m/versions.tf" || { echo "constraint drift in modules/$m/versions.tf: missing '$AZ_EXPECT'"; FAILED+=("constraints:$m"); }
done
echo "== tflint --recursive =="
"$TFLINT" --init --recursive >/dev/null || FAILED+=("tflint:init")
if ! "$TFLINT" --recursive; then FAILED+=("tflint"); fi

for m in "${MODULES[@]}"; do
  echo "== module: $m =="
  pushd "modules/$m" >/dev/null
  if ! "$TF" init -backend=false -no-color -input=false >"$TMPDIR_INIT_LOG" 2>&1; then echo "init failed for $m:"; tail -5 "$TMPDIR_INIT_LOG"; FAILED+=("$m:init"); popd >/dev/null; continue; fi
  "$TF" validate -no-color >/dev/null || FAILED+=("$m:validate")
  "$TF" test -no-color || FAILED+=("$m:test")
  popd >/dev/null
done

if [ -d examples ]; then
  echo "== examples validate (backend disabled) =="
  pushd examples >/dev/null
  "$TF" init -backend=false -no-color >/dev/null && "$TF" validate -no-color >/dev/null || FAILED+=("examples:validate")
  popd >/dev/null
fi

echo "== negative check: missing policy definition file errors clearly =="
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/cfg"
cat >"$TMP/cfg/main.tf" <<EOF
module "missing_def" {
  source          = "$PWD/modules/definition"
  policy_category = "NoSuchCategory"
  policy_name     = "no_such_policy_xyz"
}
EOF
cat >"$TMP/cfg/providers.tf" <<'EOF'
terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}

provider "azurerm" {
  features {}
}
EOF
pushd "$TMP/cfg" >/dev/null
ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000 \
ARM_TENANT_ID=00000000-0000-0000-0000-000000000000 \
ARM_CLIENT_ID=00000000-0000-0000-0000-000000000000 \
ARM_CLIENT_SECRET=dummy \
"$TF" init -backend=false -no-color >/dev/null
set +e
# a bogus certificate path makes provider auth fail locally (no valid
# credentials, no outbound token request) before the plan reports the
# expected module error
ARM_CLIENT_CERTIFICATE_PATH=/nonexistent/cert.pfx \
ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000 \
"$TF" plan -no-color >/dev/null 2>"$TMP/err.txt"
RC=$?
set -e
if [ $RC -eq 0 ]; then
  FAILED+=("negative-check: expected plan failure for missing policy file")
elif ! grep -qiE "(No policy definition file found|no such file|no file exists)" "$TMP/err.txt"; then
  FAILED+=("negative-check: error did not surface a file-read message")
else
  echo "OK: missing definition file fails the plan with a clear file error"
fi
popd >/dev/null

echo "== negative check: initiative parameter merge conflicts fail fast (#7) =="
TMP2=$(mktemp -d)
trap 'rm -rf "$TMP" "$TMP2"' EXIT
mkdir -p "$TMP2/cfg"
cat >"$TMP2/cfg/main.tf" <<EOF
module "conflicting_initiative" {
  source                  = "$PWD/modules/initiative"
  initiative_name         = "conflict_probe"
  initiative_display_name = "Conflict Probe"
  management_group_id     = "/providers/Microsoft.Management/managementGroups/probe"

  member_definitions = [
    {
      id           = "/providers/Microsoft.Authorization/policyDefinitions/conflict_a"
      name         = "conflict_a"
      display_name = "Conflict A"
      mode         = "All"
      metadata     = jsonencode({ category = "Monitoring" })
      parameters   = jsonencode({ sharedParam = { type = "String", defaultValue = "alpha", metadata = { displayName = "Shared" } } })
      policy_rule  = jsonencode({ if = {}, then = {} })
    },
    {
      id           = "/providers/Microsoft.Authorization/policyDefinitions/conflict_b"
      name         = "conflict_b"
      display_name = "Conflict B"
      mode         = "All"
      metadata     = jsonencode({ category = "Monitoring" })
      parameters   = jsonencode({ sharedParam = { type = "String", defaultValue = "beta", metadata = { displayName = "Shared" } } })
      policy_rule  = jsonencode({ if = {}, then = {} })
    }
  ]
}
EOF
cp "$TMP/cfg/providers.tf" "$TMP2/cfg/providers.tf"
pushd "$TMP2/cfg" >/dev/null
ARM_CLIENT_CERTIFICATE_PATH=/nonexistent/cert.pfx \
ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000 \
"$TF" init -backend=false -no-color >/dev/null
set +e
ARM_CLIENT_CERTIFICATE_PATH=/nonexistent/cert.pfx \
ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000 \
"$TF" plan -no-color >/dev/null 2>"$TMP2/err.txt"
RC=$?
set -e
if [ $RC -eq 0 ]; then
  FAILED+=("negative-check-params: expected plan failure for conflicting parameter schemas")
elif ! grep -qi "conflicting parameter schemas" "$TMP2/err.txt"; then
  FAILED+=("negative-check-params: error did not surface the conflict diagnostic")
else
  echo "OK: incompatible initiative parameter schemas fail the plan with a clear diagnostic"
fi
popd >/dev/null

echo "== negative check: typed object contracts reject malformed structures (#4) =="
TMP4=$(mktemp -d)
mkdir -p "$TMP4/cfg"
cat >"$TMP4/cfg/main.tf" <<EOF
module "bad_initiative" {
  source                  = "$PWD/modules/initiative"
  initiative_name         = "typed_contract_probe"
  initiative_display_name = "Typed Contract Probe"
  management_group_id     = "/providers/Microsoft.Management/managementGroups/probe"
  member_definitions      = [{ id = "/providers/Microsoft.Authorization/policyDefinitions/broken" }]
}
EOF
cat >"$TMP4/cfg/providers.tf" <<EOF
terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}

provider "azurerm" {
  features {}
}
EOF
pushd "$TMP4/cfg" >/dev/null
"$TF" init -backend=false -no-color >/dev/null
set +e
ARM_CLIENT_CERTIFICATE_PATH=/nonexistent/cert.pfx \
ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000 \
"$TF" plan -no-color >/dev/null 2>"$TMP4/err.txt"
RC=$?
set -e
if [ $RC -eq 0 ]; then
  FAILED+=("negative-check-typed: expected plan failure for malformed member_definitions")
elif ! grep -qi "Invalid value for input variable" "$TMP4/err.txt"; then
  FAILED+=("negative-check-typed: did not surface a type-contract error")
else
  echo "OK: malformed member_definitions rejected by the type contract"
fi
popd >/dev/null

echo "== negative check: legacy map-shaped overrides rejected (#8) =="
TMP5=$(mktemp -d)
mkdir -p "$TMP5/cfg"
cat >"$TMP5/cfg/main.tf" <<EOF
module "legacy_overrides" {
  source           = "$PWD/modules/set_assignment"
  assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
  overrides = [
    {
      effect    = "Deny"
      selectors = { in = ["a"] }
    }
  ]
}
EOF
cp "$TMP/cfg/providers.tf" "$TMP5/cfg/providers.tf"
pushd "$TMP5/cfg" >/dev/null
ARM_CLIENT_CERTIFICATE_PATH=/nonexistent/cert.pfx \
ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000 \
"$TF" init -backend=false -no-color >/dev/null
set +e
ARM_CLIENT_CERTIFICATE_PATH=/nonexistent/cert.pfx \
ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000 \
"$TF" plan -no-color >/dev/null 2>"$TMP5/err.txt"
RC5=$?
set -e
if [ $RC5 -eq 0 ]; then
  FAILED+=("negative-check-overrides: expected plan failure for legacy map-shaped overrides")
elif ! grep -qiE "(unsupported argument|an argument named .effect.|missing required argument)" "$TMP5/err.txt"; then
  FAILED+=("negative-check-overrides: did not surface a type-contract error")
else
  echo "OK: legacy map-shaped overrides rejected by the type contract"
fi
popd >/dev/null

echo "== negative check: unknown remediation_reference_ids fail fast (#1/#3) =="
TMP3=$(mktemp -d)
trap 'rm -rf "$TMP" "$TMP2" "$TMP3" "$TMP4" "$TMP5"' EXIT
mkdir -p "$TMP3/cfg"
cat >"$TMP3/cfg/main.tf" <<EOF
module "unknown_ref_assignment" {
  source           = "$PWD/modules/set_assignment"
  assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
  remediation_reference_ids = ["nonexistent_ref"]

  initiative = {
    id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/probe_initiative"
    name                = "probe_initiative"
    display_name        = "Probe Initiative"
    description         = "Probe"
    management_group_id = null
    parameters          = {}
    metadata            = jsonencode({ category = "Probe" })
    role_definition_ids = []
    replace_trigger     = "abc"
    policy_definition_reference = [
      { policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/m1", reference_id = "real_member", parameter_values = jsonencode({ effect = { value = "DeployIfNotExists" } }) }
    ]
  }
}
EOF
cp "$TMP/cfg/providers.tf" "$TMP3/cfg/providers.tf"
pushd "$TMP3/cfg" >/dev/null
ARM_CLIENT_CERTIFICATE_PATH=/nonexistent/cert.pfx \
ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000 \
"$TF" init -backend=false -no-color >/dev/null
set +e
ARM_CLIENT_CERTIFICATE_PATH=/nonexistent/cert.pfx \
ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000 \
"$TF" plan -no-color >/dev/null 2>"$TMP3/err.txt"
RC=$?
set -e
if [ $RC -eq 0 ]; then
  FAILED+=("negative-check-refids: expected plan failure for unknown remediation reference ids")
elif ! grep -qi "are not valid member references" "$TMP3/err.txt"; then
  FAILED+=("negative-check-refids: error did not surface the unknown-reference diagnostic")
else
  echo "OK: unknown remediation reference ids fail the plan with a clear diagnostic"
fi
popd >/dev/null

if [ ${#FAILED[@]} -gt 0 ]; then
  echo "FAILED: ${FAILED[*]}"
  exit 1
fi
echo "ALL OFFLINE GATES PASSED"
