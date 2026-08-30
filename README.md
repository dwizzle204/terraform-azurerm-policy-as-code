<!-- markdownlint-configure-file { "MD004": { "style": "consistent" } } -->
<!-- markdownlint-disable MD033 -->
<p align="center">
  <a href="https://learn.microsoft.com/en-us/azure/governance/policy/">
      <img src="img/logo.svg" width="600" alt="Terraform-Azure-Policy-as-Code">
  </a>
  <br>
  <h1 align="center">Azure Policy as Code with Terraform</h1>
  <p align="center">
    <a href="https://github.com/gettek/terraform-azurerm-policy-as-code/actions/workflows/cd.yml"><img src="https://github.com/gettek/terraform-azurerm-policy-as-code/actions/workflows/cd.yml/badge.svg?branch=main" alt="CD Tests"></a>
    <a href="https://github.com/gettek/terraform-azurerm-policy-as-code/actions/workflows/ci.yml"><img src="https://github.com/gettek/terraform-azurerm-policy-as-code/actions/workflows/ci.yml/badge.svg" alt="CI Tests"></a></br>
    <a href="https://github.com/gettek/terraform-azurerm-policy-as-code/discussions"><img src="https://img.shields.io/badge/topic-discussions-yellowgreen.svg" alt="Go to topic discussions"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-orange.svg" alt="MIT License"></a></br>
    <a href="https://github.dev/gettek/terraform-azurerm-policy-as-code"><img src="https://img.shields.io/static/v1?logo=refinedgithub&label=&message=Open%20in%20Visual%20Studio%20Code&labelColor=2c2c32&color=007acc&logoColor=007acc" alt="Open in VSCode"></a>
    </br>
    <a href="https://registry.terraform.io/modules/gettek/policy-as-code/azurerm/"><img src="https://img.shields.io/badge/dynamic/json?url=https://registry.terraform.io/v2/modules/gettek/policy-as-code/azurerm/downloads/summary&logo=terraform&label=Registry%20Downloads&query=$.data.attributes.total&color=844FBA&logoColor=844FBA" alt="Terraform Registry"></a>
  </p>
</p>
<!-- markdownlint-enable MD033 -->

- [Repo Folder Structure](#repo-folder-structure)
- [Custom Policy Definitions Module](#custom-policy-definitions-module)
- [Policy Initiative (Set Definitions) Module](#policy-initiative-set-definitions-module)
- [Policy Definition Assignment Module](#policy-definition-assignment-module)
- [Policy Initiative Assignment Module](#policy-initiative-assignment-module)
- [Policy Exemption Module](#policy-exemption-module)
- [Data-Driven Intent Interface](#data-driven-intent-interface)
- [Achieving Continuous Compliance](#achieving-continuous-compliance)
  - [⚙️Assignment Effects](#️assignment-effects)
  - [👥Role Assignments](#role-assignments)
    - [Customizing](#customizing)
    - [Conditions for Skipping](#conditions-for-skipping)
    - [Required Permissions](#required-permissions)
  - [✅Remediation Tasks](#remediation-tasks)
  - [⏱️On-demand evaluation scan](#️on-demand-evaluation-scan)
  - [🎯Definition and Assignment Scopes](#definition-and-assignment-scopes)
- [📗Useful Resources](#useful-resources)
  - [GitHub](#github)
  - [Microsoft](#microsoft)
  - [Terraform](#terraform)
  - [Tools](#tools)
- [Governance & Operations Guides](#governance--operations-guides)
- [Limitations](#limitations)

## Compatibility & Testing

Supported Terraform/provider versions: [COMPATIBILITY.md](COMPATIBILITY.md).

## Versioning: catalog metadata vs Azure definitionVersion selectors

These are two distinct concepts and are kept separate (issue [#59](https://github.com/dwizzle204/terraform-azurerm-policy-as-code/issues/59)):

- **Organizational catalog version** — a free-form `metadata.version` on a custom policy definition (e.g. `"1.0.0"`) describes your content/catalog versioning. It is retained as `catalog_version` and never changes initiative reference semantics.
- **Azure `definitionVersion` selector** — the `policy_definition_reference.version` attribute selects a *built-in* definition version (AzureRM grammar `{major}.{minor}[.*][-preview]`, e.g. `3.1`, `3.1.*`, `1.0.*-preview`). It is only emitted when you explicitly supply `version` on a member definition; ordinary module-created custom definitions emit no selector because no Azure Policy Definition Version resource is created or resolved on their behalf.

If native custom-definition version resources are adopted later, they will be modeled explicitly and will not be inferred from catalog metadata.

## Testing

This repository uses a layered, credential-free test strategy: fmt → tflint → constraint-consistency → per-module init/validate/`terraform test` with mocked providers (6 modules, 80+ runs, Terraform 1.11 + 1.15 matrix in CI) → 3 example-root validations → 7 expected-failure negative checks → isolated opt-in live-Azure suite. Normal PR validation requires no Azure tenant or credentials. See [TESTING.md](TESTING.md); run everything locally with `./scripts/test.sh`.


## What's New — Maintenance Program

| Capability | Issue | Notes / migration |
|------------|-------|-------------------|
| Provider compatibility matrix | [#9](https://github.com/dwizzle204/terraform-azurerm-policy-as-code/issues/9) | Unified floors (`TF >= 1.11`, azurerm `>=4.35,<6.0`); see [COMPATIBILITY.md](COMPATIBILITY.md) |
| Fail-fast missing policy files | [#5](https://github.com/dwizzle204/terraform-azurerm-policy-as-code/issues/5) | No silent `{}` fallback; runtime-only definitions still supported |
| Deterministic definition names | [#6](https://github.com/dwizzle204/terraform-azurerm-policy-as-code/issues/6) | Hash suffix replaces random; migration notes in module README |
| Collision-resistant assignment names (opt-in) | [#2](https://github.com/dwizzle204/terraform-azurerm-policy-as-code/issues/2) | `collision_resistant_naming = true`; default unchanged |
| Initiative parameter conflict detection | [#7](https://github.com/dwizzle204/terraform-azurerm-policy-as-code/issues/7) | Incompatible duplicate schemas fail plan; `merge_parameters=false` escape hatch |
| Effect-filtered, opt-in remediation | [#1](https://github.com/dwizzle204/terraform-azurerm-policy-as-code/issues/1) [#3](https://github.com/dwizzle204/terraform-azurerm-policy-as-code/issues/3) | `remediate_effects`/`remediation_reference_ids`; assignment-only deployments need no RBAC/remediation privileges |
| Typed input contracts | [#4](https://github.com/dwizzle204/terraform-azurerm-policy-as-code/issues/4) | Remaining `any` documented in COMPATIBILITY.md |
| Full override/resource-selector contracts | [#8](https://github.com/dwizzle204/terraform-azurerm-policy-as-code/issues/8) | Typed kinds with validation; staged-rollout examples |
| Governed exemption lifecycle | [#10](https://github.com/dwizzle204/terraform-azurerm-policy-as-code/issues/10) | Optional `governed` contract: ownership, tracking, expiry validation |
| Data-driven intent interface | [#13](https://github.com/dwizzle204/terraform-azurerm-policy-as-code/issues/13) | See below; YAML-driven example in `examples-intent/` |

## Repo Folder Structure

```bash
📦examples
📦docs (governance & operations guides)
📦examples-intent (YAML-driven consumer example)
📦modules
  └──📂def_assignment
  └──📂definition
  └──📂exemption
  └──📂initiative
  └──📂intent
  └──📂set_assignment
📦policies
  └──📂policy_category (e.g. General, should correspond to [var.policy_category])
      └──📜policy_name.json (e.g. whitelist_regions, should correspond to [var.policy_name])
📦scripts
  ├──📂dsc_examples
  └──📜build_machine_config_packages.ps1 (build and publish custom guest configuration packages)
```

## [Custom Policy Definitions Module](modules/definition)

This module depends on populating `var.policy_name` and `var.policy_category` to correspond with the respective custom policy definition `json` file found in the [local library](policies). You can also parse in other template files and data sources at runtime, see the [module readme](modules/definition) for examples and acceptable inputs.

```hcl
module whitelist_regions {
  source              = "gettek/policy-as-code/azurerm//modules/definition"
  policy_name         = "whitelist_regions"
  display_name        = "Allow resources only in whitelisted regions"
  policy_category     = "General"
  management_group_id = data.azurerm_management_group.org.id
}
```

> 📘 [Microsoft Docs: Azure Policy definition structure](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/definition-structure)

## [Policy Initiative (Set Definitions) Module](modules/initiative)

Dynamically create a policy set based on multiple custom or built-in policy definition references to simplify assignments.


```hcl
module platform_baseline_initiative {
  source                  = "gettek/policy-as-code/azurerm//modules/initiative"
  initiative_name         = "platform_baseline_initiative"
  initiative_display_name = "[Platform]: Baseline Policy Set"
  initiative_description  = "Collection of policies representing the baseline platform requirements"
  initiative_category     = "General"
  management_group_id     = data.azurerm_management_group.org.id

  member_definitions = [
    module.whitelist_resources.definition,
    module.whitelist_regions.definition
  ]
}
```

> 📘 [Microsoft Docs: Azure Policy initiative definition structure](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/initiative-definition-structure)

## [Policy Definition Assignment Module](modules/def_assignment)

```hcl
module org_mg_whitelist_regions {
  source            = "gettek/policy-as-code/azurerm//modules/def_assignment"
  definition        = module.whitelist_regions.definition
  assignment_scope  = data.azurerm_management_group.org.id
  assignment_effect = "Deny"

  assignment_parameters = {
    listOfRegionsAllowed = [
      "UK South",
      "UK West",
      "Global"
    ]
  }
}
```

> 📘 [Microsoft Docs: Azure Policy assignment structure](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/assignment-structure)

## [Policy Initiative Assignment Module](modules/set_assignment)

```hcl
module org_mg_platform_diagnostics_initiative {
  source                  = "gettek/policy-as-code/azurerm//modules/set_assignment"
  initiative              = module.platform_diagnostics_initiative.initiative
  assignment_scope        = data.azurerm_management_group.org.id
  assignment_effect       = "DeployIfNotExists"

  # optional resource remediation inputs
  re_evaluate_compliance  = false
  skip_remediation        = false
  skip_role_assignment    = false
  remediation_scope       = data.azurerm_subscription.current.id

  assignment_parameters = {
    workspaceId                 = data.azurerm_log_analytics_workspace.workspace.id
    storageAccountId            = data.azurerm_storage_account.sa.id
    eventHubName                = data.azurerm_eventhub_namespace.ehn.name
    eventHubAuthorizationRuleId = data.azurerm_eventhub_namespace_authorization_rule.ehr.id
    metricsEnabled              = "True"
    logsEnabled                 = "True"
  }

  assignment_not_scopes = [
    data.azurerm_management_group.team_a.id
  ]

  non_compliance_messages = module.platform_diagnostics_initiative.non_compliance_messages
}
```

## [Policy Intent Module](modules/intent)

The intent module is a thin, data-driven orchestrator over the definition, initiative, assignment and exemption modules. Consumers declare typed maps of intent (optionally decoded from YAML/JSON) and never select scope-specific AzureRM resources.

## [Policy Exemption Module](modules/exemption)

Use the exemption module in favour of `not_scopes` to create an auditable time-sensitive Policy exemption

```hcl
module exemption_team_a_mg_deny_nic_public_ip {
  source               = "gettek/policy-as-code/azurerm//modules/exemption"
  name                 = "Deny NIC Public IP Exemption"
  display_name         = "Exempted while testing"
  description          = "Allows NIC Public IPs for testing"
  scope                = data.azurerm_management_group.team_a.id
  policy_assignment_id = module.team_a_mg_deny_nic_public_ip.id
  exemption_category   = "Waiver"
  expires_on           = "2023-05-25" # optional

  # optional
  metadata = {
    requested_by  = "Team A"
    approved_by   = "Mr Smith"
    approved_date = "2021-11-30"
    ticket_ref    = "1923"
  }
}
```

> 📘 [Microsoft Docs: Azure Policy exemption structure](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/exemption-structure)

## Data-Driven Intent Interface

The [`modules/intent`](modules/intent) wrapper turns small typed maps into definitions → initiatives → assignments → exemptions using the existing modules — no scope-specific resource selection and no new resource types:

```hcl
module "intent" {
  source = "./modules/intent"

  definitions = {
    deploy_vnet_logs = { category = "Monitoring", policy_name = "deploy_vnet_diagnostic_setting" }
  }
  initiatives = {
    platform_baseline = {
      display_name           = "Platform Baseline"
      management_group_id    = var.root_mgmt_group_id
      member_definition_keys = ["deploy_vnet_logs"]
      metadata               = { controlIds = ["AZC-01"] } # catalog/control IDs flow into Azure metadata
    }
  }
  assignments = {
    platform = { initiative_key = "platform_baseline", scope = var.root_mgmt_group_id }
  }
}
```

See `examples-intent/` for a full YAML-driven pattern (`yamldecode` at the root; no extra providers). Governance metadata patterns: [docs/GOVERNANCE_INTEGRATION.md](docs/GOVERNANCE_INTEGRATION.md).

## Achieving Continuous Compliance

### ⚙️Assignment Effects

Azure Policy supports the following types of effect:

![Types Policy Effects from least to most restrictive](img/effects.svg)

> 💡 **Note:** If you're managing tags, it's recommended to use `Modify` instead of `Append` as Modify provides additional operation types and the ability to remediate existing resources. However, Append is recommended if you aren't able to create a managed identity or Modify doesn't yet support the alias for the resource property.

> 📘 [Microsoft Docs: Understand how effects work](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/effects)

### 👥Role Assignments

Role assignments and remediation tasks are automatically created by the `*_assignment` modules if a Policy Definition's `policyRule` includes a list of `roleDefinitionIds`.

#### Customizing

You can override these default role assignments using the `role_definition_ids` parameter, as demonstrated in [this example](examples/assignments_org.tf#L90).

By default, role assignment scopes match the policy assignment scope. However, this can be customized using the `role_assignment_scope` parameter.

Alternatively, to disable role assignment creation entirely, set: `skip_role_assignment = true`

#### Conditions for Skipping

Role assignments are automatically skipped when either of the following is explicitly used:
- AAD Group Memberships (`aad_group_remediation_object_ids`)
- User Managed Identities (`identity_ids`)

#### Required Permissions

To successfully create role assignments, ensure the deployment account has the appropriate permissions:

- **For Role Assignment**:
  The deployment account requires the [User Access Administrator](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#user-access-administrator) role at either:
  - `assignment_scope` (less preferred)
  - `definition_scope` (recommended)

- **For AAD Group Membership**:
  The deployment principal must have the following Microsoft Graph API (Application) permissions:
  - `Group.Read.All`
  - `GroupMember.ReadWrite.All`

### ✅Remediation Tasks

Remediation tasks are **opt-in and effect-filtered**. By default no remediation tasks are created. Enable them by:

- **Intent interface** (`modules/intent`): set `remediate = true` on the assignment intent (default `false`). Optionally restrict with `remediate_effects` (defaults to `["DeployIfNotExists", "Modify"]` when remediation is enabled) or select explicit members via `remediation_reference_ids`.
- **Direct assignment modules** (`modules/set_assignment` / `modules/def_assignment`): populate `remediate_effects` with the effects you want remediated (e.g. `["DeployIfNotExists", "Modify"]`) and ensure the assignment has an identity (via `role_definition_ids` or the initiative's roles). Members whose resolved effect is in `remediate_effects` produce one remediation task per eligible reference. `remediation_reference_ids` is an escape hatch only for members whose effect is unresolved (empty) — known non-remediable effects remain rejected even when explicitly listed.

You can still suppress remediation with `skip_remediation = true` for assignment-only deployments, and suppress RBAC provisioning with `skip_role_assignment = true` when using a pre-authorized identity (`identity_ids` / externally managed RBAC).

### ⏱️On-demand evaluation scan

To trigger an on-demand [compliance scan](https://learn.microsoft.com/en-us/azure/governance/policy/how-to/get-compliance-data) with terraform, set `re_evaluate_compliance = true` on `*_assignment` modules, defaults to `false (ExistingNonCompliant)`.

> 💡 **Note:** `ReEvaluateCompliance` only applies to remediation at Subscription scope and below and will take longer depending on the size of your environment. Use the `remediation_scope` parameter to target a specific subscription, resource group or resource.

### 🎯Definition and Assignment Scopes

  - Should be Defined as **high up** in the hierarchy as possible.
  - Should be Assigned as **low down** in the hierarchy as possible.
  - Multiple scopes can be exempt from policy inheritance by specifying `assignment_not_scopes` or using the [exemption module](modules/exemption).
  - Policy **overrides RBAC** so even resource owners and contributors fall under compliance enforcements assigned at a higher scope (unless the policy is assigned at the ownership scope).

![Policy Definition and Assignment Scopes](img/scopes.svg)

> ⚠️ **Requirement:** Ensure the deployment account has at least the [Resource Policy Contributor](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#resource-policy-contributor) role at both `definition_scope` and `assignment_scope`.

## Governance & Operations Docs

- [Policy Catalog vs Framework](docs/POLICY_CATALOG.md) — the bundled `policies/` tree is reference content, not a production baseline
- [Remote State Architecture](docs/REMOTE_STATE.md) — vendor-neutral state isolation, locking, RBAC and blast-radius patterns
- [Governance Control Catalog Integration](docs/GOVERNANCE_INTEGRATION.md) — mapping external control IDs to policy/initiative/exemption metadata

## Governance & Operations Guides

- [Policy Catalog vs Framework](docs/POLICY_CATALOG.md) — the bundled `policies/` folder is reference content, not a maintained baseline
- [Remote State Architecture](docs/REMOTE_STATE.md) — centralized state, locking, RBAC separation of core policies from exemptions
- [Governance Catalog Integration](docs/GOVERNANCE_INTEGRATION.md) — mapping external control catalogs to Azure Policy artifacts

## Migration Summary (v3 program changes)

| Issue | Change | Migration |
|-------|--------|-----------|
| #9 | Provider/Terraform floors unified (`>= 1.11`, azurerm `>=4.35,<6.0`) | See [COMPATIBILITY.md](COMPATIBILITY.md) |
| #6 | Definition names now `<prefix>_<8-char-hash>` (was random suffix) | Existing definitions replaced on next apply — [migration notes](modules/definition/README.md#migrating-from-random-suffixed-definition-names-6) |
| #2 | Opt-in collision-resistant assignment naming (`collision_resistant_naming = true`) | Enabling replaces assignments — [notes](modules/set_assignment/README.md) |
| #7 | Conflicting initiative parameter schemas now fail plan | Align member schemas or set `merge_parameters = false` |
| #1/#3 | Remediation is opt-in and effect-filtered (`remediate_effects`) | Set `remediate_effects`/`remediation_reference_ids` to retain prior behavior — [docs](modules/set_assignment/README.md) |
| #10 | Governed exemption contract available | Optional; simple exemptions unchanged |
| #8 | Typed override/resource-selector contracts | Legacy map shapes rejected — [migration notes](modules/set_assignment/README.md#migration-notes-8) |
| #4 | Typed input contracts on definition/initiative/assignment nodes | Malformed structures now fail at plan |

## 📗Useful Resources

### GitHub

- [Azure Built-In Policies and Samples](https://github.com/Azure/azure-policy)
- [Contribute to Community Policies](https://github.com/Azure/Community-Policy)
- [Awesome Azure Policy - a collection of awesome references](https://github.com/globalbao/awesome-azure-policy)

### Microsoft

- [Azure Policy Home](https://learn.microsoft.com/en-us/azure/governance/policy/)
- [List of Builtin Policies](https://learn.microsoft.com/en-us/azure/governance/policy/samples/built-in-policies)
- [Index of Azure Policy Samples](https://learn.microsoft.com/en-us/azure/governance/policy/samples/)
- [Design Azure Policy as Code workflows](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/policy-as-code)
- [Evaluate the impact of a new Azure Policy definition](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/evaluate-impact)
- [Author policies for array properties on Azure resources](https://learn.microsoft.com/en-us/azure/governance/policy/how-to/author-policies-for-arrays)
- [Azure Policy Regulatory Compliance (Benchmarks)](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/security-controls-policy)
- [Azure Policy Exemption](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/exemption-structure)
- [Tutorial: Build policies to enforce compliance](https://learn.microsoft.com/en-us/azure/governance/policy/tutorials/create-and-manage)
- [Tutorial: Security Center - Working with security policies](https://learn.microsoft.com/en-us/azure/security-center/tutorial-security-policy)
- [VSCode Azure Policy Extension](https://marketplace.visualstudio.com/items?itemName=AzurePolicy.azurepolicyextension)

### Terraform

- [azurerm_policy_definition](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/policy_definition)
- [azurerm_policy_set_definition](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/policy_set_definition)
- [azurerm_*_policy_assignment](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_assignment)
- [azurerm_*_policy_remediation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_remediation)
- [azurerm_*_policy_exemption](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_exemption)

### Tools

- [AzAdvertizer: Release and change tracking on Azure Governance capabilities](https://www.azadvertizer.net/index.html)
- [Azure Citadel: Creating Custom Policies](https://www.azurecitadel.com/policy/custom/)

## Limitations

- `DefinitionName` and `InitiativeName` have a maximum length of **64** characters
- `AssignmentName` has maximum length of **24** characters at Management Group Scope and **64** characters at all other Scopes
- `DisplayName` has a maximum length of **128** characters and `description` a maximum length of **512** characters
- There's a [maximum count](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/azure-subscription-service-limits#azure-policy-limits) for each object type for Azure Policy. For definitions, an entry of Scope means the management group or subscription. For assignments and exemptions, an entry of Scope means the management group, subscription, resource group, or individual resource:

| Where                                                     | What                             | Maximum count |
| --------------------------------------------------------- | -------------------------------- | ------------- |
| Scope                                                     | Policy definitions               | 500           |
| Scope                                                     | Initiative definitions           | 200           |
| Tenant                                                    | Initiative definitions           | 2,500         |
| Scope                                                     | Policy or initiative assignments | 200           |
| Scope                                                     | Exemptions                       | 1,000         |
| Policy definition                                         | Parameters                       | 20            |
| Initiative definition                                     | Policies                         | 1,000         |
| Initiative definition                                     | Parameters                       | 400           |
| Policy or initiative assignments                          | Exclusions (notScopes)           | 400           |
| Policy rule                                               | Nested conditionals              | 512           |
| Remediation task                                          | Resources                        | 50,000        |
| Policy definition, initiative, or assignment request body | Bytes                            | 1,048,576     |

Policy rules have additional limits to the number of conditions and their complexity. See [Policy rule limits](https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/governance/policy/concepts/definition-structure-policy-rule.md#policy-rule-limits) for more information.

