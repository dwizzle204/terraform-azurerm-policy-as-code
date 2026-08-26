# Offline Terraform Test Strategy (Issue #16) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make normal PR validation runnable without any Azure tenant or credentials, via layered `fmt` / `init -backend=false` / `validate` / `terraform test` (mock_provider) gates, with live-Azure testing isolated into an optional separate suite.

**Architecture:** Add `*.tftest.hcl` files under each module's `tests/` directory using `mock_provider "azurerm"` (and `"azuread"` where the module consumes it). Module logic is made assertable by exposing a small number of additive outputs derived from `locals` (assignment naming/parameters) and by using distinct mock-resource IDs per scope so scope-selection logic can be asserted through existing outputs. A credential-free shell runner (`scripts/test.sh`) and a new GitHub workflow (`.github/workflows/tests.yml`) execute all offline layers in CI; the pre-existing live plan workflow (`ci.yml`) loses its `pull_request` trigger so live Azure validation is no longer part of normal PR checks. A skeleton `integration-tests/azure/` suite is added for behavior that only mocks cannot prove.

**Tech Stack:** Terraform >= 1.10 (mock_provider requires >= 1.7), azurerm provider >= 4.12, azuread provider, GitHub Actions.

**Spec:** https://github.com/dwizzle204/terraform-azurerm-policy-as-code/issues/16

## Global Constraints

- Normal PR validation MUST require no Azure credentials (`ARM_*`, storage backend keys).
- `mock_provider` requires Terraform >= 1.7; CI pins `~1.10.0` (matches existing workflows).
- Module provider floors stay untouched: azurerm `>= 4.12` (definition/initiative/set_assignment/def_assignment), `>= 3.23` (exemption).
- No changes to resource logic or existing output semantics — tests document current behavior; new outputs are strictly additive.
- Keep repo conventions: 2-space indent HCL, `terraform fmt` clean, kebab-case workflow names.

---

### Task 1: Environment prep + dev branch

**Files:** none committed.

- [ ] **Step 1: Install Terraform locally**

```bash
mkdir -p ~/.local/bin && curl -fsSL -o /tmp/tf.zip https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_linux_amd64.zip && unzip -o /tmp/tf.zip -d ~/.local/bin && ~/.local/bin/terraform version
```

Expected: `Terraform v1.10.5`.

- [ ] **Step 2: Create dev branch from main**

```bash
cd /home/dm/workspace/terraform-azurerm-policy-as-code && git checkout main && git pull origin main && git checkout -b dev/issue-16-offline-test-strategy
```

---

### Task 2: Declare missing azuread provider in def_assignment

**Files:**
- Modify: `modules/def_assignment/versions.tf`

**Interfaces:**
- Consumes: nothing.
- Produces: self-contained module init (`terraform init -backend=false`) for Task 6 test runs; `mock_provider "azuread"` becomes resolvable.

The module uses `resource "azuread_group_member" "remediation"` but never declares the provider (implicit dependency on consumers). Declare it without a version pin (consumer-controlled, same as today).

- [ ] **Step 1: Edit versions.tf**

Add inside the existing `required_providers` block:

```hcl
    azuread = {
      source = "hashicorp/azuread"
    }
```

- [ ] **Step 2: Verify init resolves both providers**

Run: `cd modules/def_assignment && terraform init -backend=false`
Expected: `- Installing hashicorp/azuread ...` plus azurerm; exit 0.

- [ ] **Step 3: Commit**

```bash
git add modules/def_assignment/versions.tf && git commit -m "chore(def_assignment): declare implicit azuread required provider"
```

---

### Task 3: Add contract-test outputs to assignment modules

**Files:**
- Modify: `modules/set_assignment/outputs.tf`
- Modify: `modules/def_assignment/outputs.tf`

**Interfaces:**
- Produces:
  - `set_assignment.assignment_name` → string (lowercase, trimmed name)
  - `set_assignment.parameters` → JSON string of merged assignment parameters (or null)
  - `def_assignment.assignment_name` → string
  - `def_assignment.parameters` → JSON string (or null)

Both mirror existing locals verbatim; purely additive so downstream consumers are unaffected.

- [ ] **Step 1: Append to `modules/set_assignment/outputs.tf`**

```hcl
output "assignment_name" {
  description = "The Policy Assignment Name (trimmed to 24 chars at management group scope)"
  value       = local.assignment_name
}

output "parameters" {
  description = "The Parameter Values assigned to this Policy Assignment"
  value       = local.parameters
}
```

- [ ] **Step 2: Append to `modules/def_assignment/outputs.tf`**

```hcl
output "assignment_name" {
  description = "The Policy Assignment Name (trimmed to 24 chars at management group scope)"
  value       = local.assignment_name
}

output "parameters" {
  description = "The Parameter Values assigned to this Policy Assignment"
  value       = local.parameters
}
```

- [ ] **Step 3: fmt + commit**

```bash
terraform fmt -recursive modules && git add modules/*/outputs.tf && git commit -m "feat(assignment): expose assignment_name and parameters outputs for contract testing"
```

---

### Task 4: Initiative module tests (offline)

**Files:**
- Create: `modules/initiative/tests/initiative.tftest.hcl`

**Interfaces:**
- Consumes: initiative module inputs (`member_definitions` nodes as produced by `definition.definition` output), outputs `parameters`, `role_definition_ids`, `non_compliance_messages`, `initiative`.
- Produces: regression net for reference/parameter merging logic.

- [ ] **Step 1: Write test file**

```hcl
mock_provider "azurerm" {}

variables {
  initiative_name         = "initiative_contract_test"
  initiative_display_name = "Initiative Contract Test"
  member_definitions = [
    {
      id           = "/providers/Microsoft.Authorization/policyDefinitions/member_a"
      name         = "member_a"
      display_name = "Member A"
      mode         = "All"
      metadata     = jsonencode({ category = "Monitoring", version = "1.0.0" })
      parameters = jsonencode({
        effect = { type = "String", defaultValue = "AuditIfNotExists", allowedValues = ["AuditIfNotExists", "Disabled"] }
        retentionDays = { type = "String", defaultValue = "30" }
      })
      policy_rule = jsonencode({ if = {}, then = { effect = "" } })
    },
    {
      id           = "/providers/Microsoft.Authorization/policyDefinitions/member_b"
      name         = "member_b"
      display_name = "member-b"
      mode         = "All"
      metadata     = jsonencode({ category = "Monitoring" })
      parameters   = jsonencode({})
      policy_rule  = jsonencode({ if = {}, then = { details = { roleDefinitionIds = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"] } } })
    }
  ]
}

run "merged_parameters_are_combined_across_members" {
  command = plan

  assert {
    condition     = length(keys(output.parameters)) == 2
    error_message = "Merged parameter set should contain exactly effect and retentionDays"
  }
  assert {
    condition     = output.parameters["effect"].defaultValue == "AuditIfNotExists"
    error_message = "Effect parameter should carry the source definition default"
  }
}

run "references_default_to_policy_names" {
  command = plan

  assert {
    condition     = [for ref in output.initiative.policy_definition_reference : ref.reference_id] == ["member_a", "member_b"]
    error_message = "Reference ids should default to policy names in order"
  }
}

run "camel_case_references_are_transformed" {
  command = plan
  variables {
    camel_case_references = true
  }

  assert {
    condition     = [for ref in output.initiative.policy_definition_reference : ref.reference_id] == ["MemberA", "MemberB"]
    error_message = "Camel case references should strip separators"
  }
}

run "role_definition_ids_collected_from_member_rules" {
  command = plan

  assert {
    condition     = output.role_definition_ids == ["/providers/microsoft.authorization/roledefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    error_message = "Role definitions from member policyRule.then.details should be collected and lowercased"
  }
}

run "non_compliance_messages_include_members_with_all_modes" {
  command = plan

  assert {
    condition     = lookup(output.non_compliance_messages, "member_a", "") != ""
    error_message = "member_a (mode All) should receive a non-compliance message entry"
  }
  assert {
    condition     = lookup(output.non_compliance_messages, null, "") == "Flagged by Initiative: initiative_contract_test"
    error_message = "Default initiative-level non-compliance message should exist under null key"
  }
}

run "duplicate_members_are_indexed" {
  command = plan
  variables {
    duplicate_members  = true
    member_definitions = [
      { id = "/providers/Microsoft.Authorization/policyDefinitions/dup", name = "dup", display_name = "Dup", mode = "All", metadata = jsonencode({ category = "Monitoring" }), parameters = jsonencode({}), policy_rule = jsonencode({}) },
      { id = "/providers/Microsoft.Authorization/policyDefinitions/dup", name = "dup", display_name = "Dup", mode = "All", metadata = jsonencode({ category = "Monitoring" }), parameters = jsonencode({}), policy_rule = jsonencode({}) }
    ]
  }

  assert {
    condition     = [for ref in output.initiative.policy_definition_reference : ref.reference_id] == ["0_dup", "1_dup"]
    error_message = "Duplicate members should be prefixed with their index"
  }
}
```

- [ ] **Step 2: Run tests**

Run: `cd modules/initiative && terraform init -backend=false && terraform test`
Expected: all 6 runs PASS. If an assertion mismatches actual upstream logic, fix the assertion to document actual verified behavior — never change module logic.

- [ ] **Step 3: Commit**

```bash
git add modules/initiative/tests && git commit -m "test(initiative): offline contract tests with mocked azurerm provider"
```

---

### Task 5: Definition module tests (offline)

**Files:**
- Create: `modules/definition/tests/fixtures/test_policy.json`
- Create: `modules/definition/tests/definition.tftest.hcl`

**Interfaces:**
- Consumes: policies library at repo root (documents path-resolution contract); `var.file_path`; outputs `name`, `metadata`, `mode`, `rules`, `parameters`.
- Produces: hermetic fixture-based coverage independent of library contents drift.

- [ ] **Step 1: Write fixture** `tests/fixtures/test_policy.json`

```json
{
  "name": "test_policy",
  "properties": {
    "displayName": "Test Policy",
    "description": "Fixture used by offline module tests",
    "mode": "Indexed",
    "metadata": { "category": "Testing", "version": "1.2.3" },
    "parameters": { "allowedLocations": { "type": "Array", "metadata": { "displayName": "Allowed locations" } } },
    "policyRule": { "if": { "field": "location", "notIn": "[[parameters('allowedLocations')]]" }, "then": { "effect": "Deny" } }
  }
}
```

- [ ] **Step 2: Write test file**

```hcl
mock_provider "azurerm" {}

variables {
  policy_category = "Testing"
  policy_name     = "nonexistent_in_library_use_fixture_instead"
}

# NOTE: the missing-file negative case cannot be asserted with terraform test
# (plan-time function errors abort the run rather than fail assertions).
# scripts/test.sh covers it with an expected-failure scratch plan.

run "loads_definition_from_file_path" {
  command = plan
  variables {
    file_path    = "${path.module}/tests/fixtures/test_policy.json"
    policy_name  = "test_policy"
    policy_category = null
  }

  assert {
    condition     = output.name == "test_policy"
    error_message = "Definition name should come from var.policy_name"
  }
  assert {
    condition     = output.metadata.category == "Testing" && output.metadata.version == "1.2.3"
    error_message = "Category and version should be read from fixture metadata"
  }
  assert {
    condition     = output.mode == "Indexed"
    error_message = "Mode should be read from the fixture properties.mode"
  }
  assert {
    condition     = jsondecode(jsonencode(output.rules)).then.effect == "Deny"
    error_message = "Policy rule should be loaded from the fixture"
  }
}

run "runtime_overrides_take_precedence_over_file" {
  command = plan
  variables {
    file_path       = "${path.module}/tests/fixtures/test_policy.json"
    policy_name     = "test_policy"
    policy_category = null
    policy_version  = "9.9.9"
    policy_mode     = "All"
  }

  assert {
    condition     = output.metadata.version == "9.9.9" && output.mode == "All"
    error_message = "Explicit runtime inputs must override library attributes"
  }
}

run "library_path_resolution_from_repo_root" {
  command = plan
  variables {
    policy_category = "Security"
    policy_name     = "deploy_asc_standard"
  }

  assert {
    condition     = output.name == "deploy_asc_standard"
    error_message = "Library resolution via path.cwd/../policies must load the named definition"
  }
}
```

Note: verify `policies/Security/deploy_asc_standard.json` exists before relying on it; substitute any real category/name pair present in the repo library.

- [ ] **Step 3: Run tests**

Run: `cd modules/definition && terraform init -backend=false && terraform test`
Expected: 3 runs PASS.

- [ ] **Step 4: Commit**

```bash
git add modules/definition/tests && git commit -m "test(definition): offline tests covering file_path, precedence and library resolution"
```

---

### Task 6: Set assignment tests (offline)

**Files:**
- Create: `modules/set_assignment/tests/set_assignment.tftest.hcl`

**Interfaces:**
- Consumes: `var.initiative` object node (as produced by `initiative.initiative` output), new outputs `assignment_name`/`parameters`, existing outputs `id`, `remediation_tasks`, `principal_id`.
- Produces: scope-selection, naming-trim, identity and remediation-filtering regression net.

- [ ] **Step 1: Write test file**

```hcl
mock_provider "azurerm" {
  mock_resource "azurerm_management_group_policy_assignment" { attributes = { id = "mock-mg-assignment-id" } }
  mock_resource "azurerm_subscription_policy_assignment" { attributes = { id = "mock-sub-assignment-id" } }
  mock_resource "azurerm_resource_group_policy_assignment" { attributes = { id = "mock-rg-assignment-id" } }
  mock_resource "azurerm_resource_policy_assignment" { attributes = { id = "mock-resource-assignment-id" } }
  mock_resource "azurerm_management_group_policy_remediation" { attributes = { id = "mock-mg-remediation-id" } }
  mock_resource "azurerm_subscription_policy_remediation" { attributes = { id = "mock-sub-remediation-id" } }
}

mock_provider "azuread" {}

variables {
  assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
  initiative = {
    id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/mock_initiative"
    name                = "mock_initiative"
    display_name        = "Mock Initiative"
    description         = "Mock"
    management_group_id = null
    parameters          = {}
    metadata            = jsonencode({ category = "Mock" })
    role_definition_ids = []
    replace_trigger     = "abc"
    policy_definition_reference = []
  }
}

run "subscription_scope_selects_subscription_assignment" {
  command = plan

  assert {
    condition     = output.id == "mock-sub-assignment-id"
    error_message = "A subscription scope must create the subscription-scoped assignment resource"
  }
}

run "management_group_scope_selects_mg_assignment_and_trims_name" {
  command = plan
  variables {
    assignment_scope = "/providers/Microsoft.Management/managementGroups/preview"
    initiative = merge(var.initiative, { name = "this_initiative_name_is_longer_than_twenty_four" })
  }

  assert {
    condition     = output.id == "mock-mg-assignment-id"
    error_message = "An MG scope must create the MG-scoped assignment resource"
  }
  assert {
    condition     = output.assignment_name == "this_initiative_name_is_lo" && length(output.assignment_name) == 24
    error_message = "Assignment names at MG scope must be lowercased and trimmed to 24 chars"
  }
}

run "resource_group_scope_selects_rg_assignment" {
  command = plan
  variables {
    assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-1"
  }

  assert {
    condition     = output.id == "mock-rg-assignment-id"
    error_message = "An RG scope must create the RG-scoped assignment resource"
  }
}

run "no_identity_means_no_remediation_or_principal" {
  command = plan

  assert {
    condition     = length(output.remediation_tasks) == 0
    error_message = "Remediation tasks require a managed identity"
  }
  assert {
    condition     = output.principal_id == null
    error_message = "No managed identity means no principal id"
  }
}

run "identity_and_dine_reference_creates_remediation" {
  command = plan
  variables {
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1
    error_message = "A DINE member with SystemAssigned identity should produce one remediation task"
  }
  assert {
    condition     = output.remediation_tasks[0].policy_definition_reference_id == "dine_member"
    error_message = "Remediation task must reference the DINE member definition"
  }
}

run "skip_remediation_suppresses_remediation_tasks" {
  command = plan
  variables {
    skip_remediation    = true
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        { policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member", reference_id = "dine_member", parameter_values = jsonencode({}) }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 0
    error_message = "skip_remediation=true must suppress remediation tasks"
  }
}

run "assignment_effect_is_merged_into_parameters" {
  command = plan
  variables {
    assignment_effect      = "Audit"
    assignment_parameters  = { retentionDays = 90 }
  }

  assert {
    condition     = jsondecode(output.parameters)["effect"].value == "Audit" && jsondecode(output.parameters)["retentionDays"].value == 90
    error_message = "assignment_effect must merge into parameter values alongside explicit parameters"
  }
}
```

- [ ] **Step 2: Run tests**

Run: `cd modules/set_assignment && terraform init -backend=false && terraform test`
Expected: 7 runs PASS (adjust assertions to observed-but-verified behavior where mocks differ; do not modify module logic).

- [ ] **Step 3: Commit**

```bash
git add modules/set_assignment/tests && git commit -m "test(set_assignment): offline scope/naming/remediation/effect tests with mocked providers"
```

---

### Task 7: Def assignment tests (offline)

**Files:**
- Create: `modules/def_assignment/tests/def_assignment.tftest.hcl`

**Interfaces:**
- Consumes: `var.definition` node (as produced by `definition.definition` output), outputs `id`, `assignment_name`, `parameters`, `role_definition_ids`, `remediation_id`.

- [ ] **Step 1: Write test file**

```hcl
mock_provider "azurerm" {
  mock_resource "azurerm_management_group_policy_assignment" { attributes = { id = "mock-mg-assignment-id" } }
  mock_resource "azurerm_subscription_policy_assignment" { attributes = { id = "mock-sub-assignment-id" } }
  mock_resource "azurerm_resource_group_policy_assignment" { attributes = { id = "mock-rg-assignment-id" } }
  mock_resource "azurerm_resource_policy_assignment" { attributes = { id = "mock-resource-assignment-id" } }
  mock_resource "azurerm_role_assignment" { attributes = { id = "mock-role-assignment-id", name = "mock-role-assignment", principal_id = "mock-principal", role_definition_id = "mock-role-def", scope = "mock-scope" } }
  mock_resource "azurerm_management_group_policy_remediation" { attributes = { id = "mock-mg-remediation-id" } }
  mock_resource "azurerm_subscription_policy_remediation" { attributes = { id = "mock-sub-remediation-id" } }
}

mock_provider "azuread" {}

variables {
  assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
  definition = {
    id                  = "/providers/Microsoft.Authorization/policyDefinitions/mock_definition"
    name                = "mock_definition_name_exceeding_twentyfour_chars"
    display_name        = "Mock Definition"
    description         = "Mock"
    mode                = "All"
    management_group_id = null
    metadata            = jsonencode({ category = "Mock" })
    parameters          = jsonencode({})
    policy_rule         = jsonencode({ if = {}, then = {} })
  }
}

run "subscription_scope_selects_subscription_assignment" {
  command = plan

  assert {
    condition     = output.id == "mock-sub-assignment-id"
    error_message = "Subscription scope must select the subscription assignment resource"
  }
}

run "mg_scope_trims_assignment_name_to_24_chars" {
  command = plan
  variables {
    assignment_scope = "/providers/Microsoft.Management/managementGroups/preview"
  }

  assert {
    condition     = output.id == "mock-mg-assignment-id"
    error_message = "MG scope must select the MG assignment resource"
  }
  assert {
    condition     = length(output.assignment_name) == 24
    error_message = "MG scoped names must trim to 24 chars"
  }
}

run "explicit_role_definitions_pass_through" {
  command = plan
  variables {
    role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
  }

  assert {
    condition     = output.role_definition_ids == ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    error_message = "Explicit role definitions must pass through unchanged"
  }
}

run "skip_remediation_removes_remediation_task" {
  command = plan
  variables {
    skip_remediation    = true
    role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
  }

  assert {
    condition     = output.remediation_id == null || output.remediation_id == ""
    error_message = "skip_remediation must prevent remediation task creation"
  }
}

run "identity_and_remediation_enabled_creates_task" {
  command = plan
  variables {
    role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
  }

  assert {
    condition     = output.remediation_id != null && output.remediation_id != ""
    error_message = "DINE-capable identity assignment should create a remediation task"
  }
}
```

- [ ] **Step 2: Run tests**

Run: `cd modules/def_assignment && terraform init -backend=false && terraform test`
Expected: 5 runs PASS.

- [ ] **Step 3: Commit**

```bash
git add modules/def_assignment/tests && git commit -m "test(def_assignment): offline scope/naming/remediation tests with mocked providers"
```

---

### Task 8: Exemption module tests (offline)

**Files:**
- Create: `modules/exemption/tests/exemption.tftest.hcl`

- [ ] **Step 1: Write test file**

```hcl
mock_provider "azurerm" {
  mock_resource "azurerm_management_group_policy_exemption" { attributes = { id = "mock-mg-exemption-id" } }
  mock_resource "azurerm_subscription_policy_exemption" { attributes = { id = "mock-sub-exemption-id" } }
  mock_resource "azurerm_resource_group_policy_exemption" { attributes = { id = "mock-rg-exemption-id" } }
  mock_resource "azurerm_resource_policy_exemption" { attributes = { id = "mock-resource-exemption-id" } }
}

variables {
  name                  = "exemption_contract_test"
  display_name          = "Exemption Contract Test"
  description           = "Offline contract test exemption"
  scope                 = "/subscriptions/00000000-0000-0000-0000-000000000000"
  policy_assignment_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock_assignment"
}

run "subscription_scope_selects_subscription_exemption" {
  command = plan

  assert {
    condition     = output.exemption.id == "mock-sub-exemption-id"
    error_message = "Subscription scope must select the subscription exemption resource"
  }
  assert {
    condition     = output.exemption.category == "Waiver"
    error_message = "Default exemption category must be Waiver"
  }
  assert {
    condition     = output.exemption.expires_on == null
    error_message = "No expiry by default"
  }
}

run "expires_on_gets_time_component" {
  command = plan
  variables {
    expires_on = "2030-01-31"
  }

  assert {
    condition     = output.exemption.expires_on == "2030-01-31T23:00:00Z"
    error_message = "Date-only expiry must be normalized with a time component"
  }
}

run "camel_case_references_are_converted" {
  command = plan
  variables {
    policy_definition_reference_ids = ["deploy_asc_standard", "member_two"]
    camel_case_references           = true
  }

  assert {
    condition     = output.exemption.definition_reference_ids == ["DeployAscStandard", "MemberTwo"]
    error_message = "camel_case_references=true must convert snake/kebab references to CamelCase"
  }
}

run "metadata_is_json_encoded" {
  command = plan
  variables {
    metadata = { requestedBy = "platform-team" }
  }

  assert {
    condition     = jsondecode(output.exemption.metadata).requestedBy == "platform-team"
    error_message = "Metadata object must be JSON encoded in the exemption payload"
  }
}
```

- [ ] **Step 2: Run tests**

Run: `cd modules/exemption && terraform init -backend=false && terraform test`
Expected: 4 runs PASS.

- [ ] **Step 3: Commit**

```bash
git add modules/exemption/tests && git commit -m "test(exemption): offline scope/category/expiry/reference tests with mocked azurerm"
```

---

### Task 9: Credential-free test runner script

**Files:**
- Create: `scripts/test.sh`

- [ ] **Step 1: Write script**

```bash
#!/usr/bin/env bash
# Credential-free validation gate for terraform-azurerm-policy-as-code (issue #16)
# Layers: fmt -> per-module init/validate/test -> missing-definition negative check.
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
  "$TF" init -backend=false -no-color >/dev/null || { FAILED+=("$m:init"); popd >/dev/null; continue; }
  "$TF" validate -no-color >/dev/null || FAILED+=("$m:validate")
  "$TF" test -no-color || FAILED+=("$m:test")
  popd >/dev/null
done

echo "== examples validate (backend disabled) =="
pushd examples >/dev/null
"$TF" init -backend=false -no-color >/dev/null && "$TF" validate -no-color >/dev/null || FAILED+=("examples:validate")
popd >/dev/null

echo "== negative check: missing policy definition file errors clearly =="
TMP=$(mktemp -d)
cat >"$TMP/main.tf" <<EOF
module "missing_def" {
  source          = "../../modules/definition"
  policy_category = "NoSuchCategory"
  policy_name     = "no_such_policy_xyz"
}
EOF
mkdir -p "$TMP/.terraform"
cp -r "$(pwd)/modules/definition/.terraform" "$TMP/module_cache" 2>/dev/null || true
pushd "$TMP" >/dev/null
cat > backend.tf <<'EOF'
terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}
provider "azurerm" { features {} }
EOF
ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000 \
ARM_TENANT_ID=00000000-0000-0000-0000-000000000000 \
ARM_CLIENT_ID=00000000-0000-0000-0000-000000000000 \
ARM_CLIENT_SECRET=dummy \
"$TF" init -backend=false -no-color >/dev/null
if "$TF" plan -no-color >/dev/null 2>"$TMP/err.txt"; then
  FAILED+=("negative-check: expected plan failure for missing policy file")
elif ! grep -qE "(no such file|doesn't exist|failed to read)" "$TMP/err.txt"; then
  FAILED+=("negative-check: error did not surface a file-read message")
else
  echo "OK: missing definition file fails the plan with a clear file error"
fi
popd >/dev/null
rm -rf "$TMP"

if [ ${#FAILED[@]} -gt 0 ]; then
  echo "FAILED: ${FAILED[*]}"
  exit 1
fi
echo "ALL OFFLINE GATES PASSED"
```

(The negative-check scratch dir wiring may need small adjustments at implementation time — e.g., provider cache reuse — but its pass/fail contract is fixed.)

- [ ] **Step 2: chmod + run**

Run: `chmod +x scripts/test.sh && ./scripts/test.sh`
Expected: `ALL OFFLINE GATES PASSED`.

- [ ] **Step 3: Commit**

```bash
git add scripts/test.sh && git commit -m "ci: add credential-free offline test gate script"
```

---

### Task 10: Integration test skeleton (isolated, optional)

**Files:**
- Create: `integration-tests/azure/main.tf`
- Create: `integration-tests/azure/tests/live.tftest.hcl`
- Create: `integration-tests/azure/README.md`

- [ ] **Step 1: Write `main.tf`**

```hcl
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.12"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

variable "test_subscription_id" {
  type = string
}

locals {
  test_prefix = "tfpac-live-test"
}

module "definition_live" {
  source          = "../../modules/definition"
  policy_category = "Security"
  policy_name     = "deploy_asc_standard"
}

module "assignment_live" {
  source           = "../../modules/def_assignment"
  assignment_scope = "/subscriptions/${var.test_subscription_id}"
  definition       = module.definition_live.definition
  assignment_effect = "Audit"
  skip_remediation = true
}
```

- [ ] **Step 2: Write `tests/live.tftest.hcl`**

```hcl
# LIVE Azure integration test — NOT part of normal PR validation.
# Requires ARM_SUBSCRIPTION_ID / ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_TENANT_ID
# against a disposable subscription. Run manually:
#   cd integration-tests/azure && ARM_SUBSCRIPTION_ID=... terraform test
run "live_definition_and_assignment_apply" {
  command = apply

  assert {
    condition     = can(regex("^/subscriptions/", module.assignment_live.id))
    error_message = "Live assignment should return an Azure resource id"
  }
}
```

- [ ] **Step 3: Write `README.md`** documenting purpose, prerequisites (disposable subscription, contributor creds), how to run, and why these are excluded from PR CI.

- [ ] **Step 4: Commit**

```bash
git add integration-tests && git commit -m "test: add optional live-Azure integration suite skeleton"
```

---

### Task 11: CI separation

**Files:**
- Create: `.github/workflows/tests.yml`
- Modify: `.github/workflows/ci.yml` (remove `pull_request:` trigger so the credentialed live-plan workflow stops running on PRs)

- [ ] **Step 1: Write `tests.yml`**

```yaml
name: tests

on:
  pull_request:
  push:
    branches: [main]

jobs:
  static-analysis:
    name: Static Analysis (no Azure creds)
    env:
      TF_IN_AUTOMATION: true
      TF_INPUT: false
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: ~1.10.0
      - name: Terraform Format
        run: terraform fmt -check -recursive

  offline-module-tests:
    name: Module Tests ${{ matrix.module }} (mocked providers, no Azure creds)
    env:
      TF_IN_AUTOMATION: true
      TF_INPUT: false
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        module: [definition, initiative, exemption, def_assignment, set_assignment]
    defaults:
      run:
        working-directory: modules/${{ matrix.module }}
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: ~1.10.0
          terraform_wrapper: false
      - name: Terraform Init (backend disabled)
        run: terraform init -backend=false -no-color
      - name: Terraform Validate
        run: terraform validate -no-color
      - name: Terraform Test (mocked)
        run: terraform test -no-color
```

No secrets are referenced anywhere in this file.

- [ ] **Step 2: Edit `ci.yml`** — remove the `pull_request:` trigger block so the credentialed live-plan pipeline runs only on pushes to `main`.

- [ ] **Step 3: Validate YAML** (e.g. `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/tests.yml'))"`) and commit:

```bash
git add .github/workflows && git commit -m "ci: split credential-free PR tests from live Azure plan workflow"
```

---

### Task 12: Testing documentation

**Files:**
- Create: `TESTING.md`

Content: layered strategy table (fmt / validate / terraform test / integration), local usage (`./scripts/test.sh`), what each layer proves, known limitation (missing-file negative case covered by script not tftest due to plan-error semantics), integration suite instructions, CI mapping to issue #16 acceptance criteria.

- [ ] **Step 1: Write TESTING.md, link it from README.md (small "Testing" section pointer).**
- [ ] **Step 2: Commit** `git commit -m "docs: add testing strategy guide (issue #16)"`.

---

### Task 13: Full verification + oracle review

- [ ] **Step 1:** Run `./scripts/test.sh` end-to-end → expect `ALL OFFLINE GATES PASSED`. Capture output as evidence.
- [ ] **Step 2:** Dispatch oracle subagent review of the full branch diff vs main. Resolve every DO-NOT-SHIP finding.
- [ ] **Step 3:** Push branch and open PR (base `main`) with: summary, issue linkage (`Closes #16`), evidence of each gate passing, notes on ci.yml trigger change.

## Self-Review Notes

- Spec coverage: naming/collision (Tasks 6-7), replacement naming (covered indirectly via terraform_data triggers — documented, not asserted), missing-file validation (Task 9 negative check), initiative parameter conflicts (Task 4 merge/suffix), remediation filtering (Tasks 6-7 — documents current enforcement/identity-gated behavior), exemption lifecycle (Task 8), scope parsing (Tasks 6-8), RBAC/remediation selection (Task 7), input contracts (all suites). Provider regressions + compliance state → Task 10 live suite.
- Placeholders: none — all code included; two implementation-time adjustment points called out explicitly (script cache wiring; library filename verification).
- Type consistency: outputs referenced in asserts match those produced in Task 3 and existing outputs inspected in-repo.
