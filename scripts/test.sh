#!/usr/bin/env bash
# Credential-free validation gate for terraform-azurerm-policy-as-code (issue #16)
# Layers: fmt -> per-module init/validate/test -> examples validate -> missing-definition negative check.
# Requires no Azure tenant or credentials. Terraform >= 1.7 (mock_provider) required.
set -euo pipefail

TF="${TF_BIN:-terraform}"
MODULES=(definition initiative exemption def_assignment set_assignment)
FAILED=()

command -v "$TF" >/dev/null || { echo "terraform not found"; exit 1; }

echo "== terraform fmt -check -recursive =="
if ! "$TF" fmt -check -recursive .; then FAILED+=("fmt"); fi

for m in "${MODULES[@]}"; do
  echo "== module: $m =="
  pushd "modules/$m" >/dev/null
  if ! "$TF" init -backend=false -no-color >/dev/null; then FAILED+=("$m:init"); popd >/dev/null; continue; fi
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
ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000 \
ARM_TENANT_ID=00000000-0000-0000-0000-000000000000 \
ARM_CLIENT_ID=00000000-0000-0000-0000-000000000000 \
ARM_CLIENT_SECRET=dummy \
"$TF" plan -no-color >/dev/null 2>"$TMP/err.txt"
RC=$?
set -e
if [ $RC -eq 0 ]; then
  FAILED+=("negative-check: expected plan failure for missing policy file")
elif ! grep -qiE "(no such file|no file exists|doesn't exist|failed to read)" "$TMP/err.txt"; then
  FAILED+=("negative-check: error did not surface a file-read message")
else
  echo "OK: missing definition file fails the plan with a clear file error"
fi
popd >/dev/null

if [ ${#FAILED[@]} -gt 0 ]; then
  echo "FAILED: ${FAILED[*]}"
  exit 1
fi
echo "ALL OFFLINE GATES PASSED"
