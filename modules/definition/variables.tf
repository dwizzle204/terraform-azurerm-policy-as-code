variable "management_group_id" {
  type        = string
  description = "The management group scope at which the policy will be defined. Defaults to current Subscription if omitted. Changing this forces a new resource to be created."
  default     = null
}

variable "policy_name" {
  type        = string
  description = "Name to be used for this policy, when using the module library this should correspond to the correct category folder under /policies/policy_category/policy_name. Changing this forces a new resource to be created."
  default     = ""

  validation {
    condition     = length(var.policy_name) <= 64
    error_message = "Definition names have a maximum 64 character limit, ensure this matches the filename within the local policies library."
  }
}

variable "display_name" {
  type        = string
  description = "Display Name to be used for this policy"
  default     = ""

  validation {
    condition     = length(var.display_name) <= 128
    error_message = "Definition display names have a maximum 128 character limit."
  }
}

variable "policy_description" {
  type        = string
  description = "Policy definition description"
  default     = ""

  validation {
    condition     = length(var.policy_description) <= 512
    error_message = "Definition descriptions have a maximum 512 character limit."
  }
}

variable "policy_mode" {
  type        = string
  description = "Specify which Resource Provider modes will be evaluated, defaults to All. Possible values are All, Indexed, Microsoft.Kubernetes.Data, Microsoft.KeyVault.Data or Microsoft.Network.Data"
  default     = null

  validation {
    condition     = var.policy_mode == null || var.policy_mode == "All" || var.policy_mode == "Indexed" || var.policy_mode == "Microsoft.Kubernetes.Data" || var.policy_mode == "Microsoft.KeyVault.Data" || var.policy_mode == "Microsoft.Network.Data"
    error_message = "Policy mode possible values are: All, Indexed, Microsoft.Kubernetes.Data, Microsoft.KeyVault.Data or Microsoft.Network.Data. Unless explicitly stated, Resource Provider modes only support built-in policy definitions, and exemptions are not supported at the component-level."
  }
}

variable "policy_category" {
  type        = string
  description = "The category of the policy, when using the module library this should correspond to the correct category folder under /policies/<policy_category>"
  default     = null
}

variable "policy_version" {
  type        = string
  description = "The version for this policy, if different from the one stored in the definition metadata, defaults to 1.0.0"
  default     = null
}

variable "policy_rule" {
  type        = any
  description = "The policy rule for the policy definition. This is a JSON object representing the rule that contains an if and a then block. Omitting this assumes the rules are located in the policy file"
  default     = null
  validation {
    condition     = var.policy_rule == null || (can({ for k, v in var.policy_rule : k => v }) && !can(tolist(var.policy_rule))) || can(tostring(var.policy_rule))
    error_message = "policy_rule must be an object (policyRule) or a JSON-encoded string."
  }
}

variable "policy_parameters" {
  type        = any
  description = "Parameters for the policy definition. This field is a JSON object representing the parameters of your policy definition. Omitting this assumes the parameters are located in the policy file"
  default     = null
  validation {
    condition     = var.policy_parameters == null || (can({ for k, v in var.policy_parameters : k => v }) && !can(tolist(var.policy_parameters))) || can(tostring(var.policy_parameters))
    error_message = "policy_parameters must be an object (parameters schema) or a JSON-encoded string."
  }
}

variable "policy_metadata" {
  type        = any
  description = "The metadata for the policy definition. This is a JSON object representing additional metadata that should be stored with the policy definition. Omitting this will fallback to meta in the definition or merge var.policy_category and var.policy_version"
  default     = null
  validation {
    condition     = var.policy_metadata == null || (can({ for k, v in var.policy_metadata : k => v }) && !can(tolist(var.policy_metadata))) || can(tostring(var.policy_metadata))
    error_message = "policy_metadata must be an object or a JSON-encoded string."
  }
  # (list exclusion kept consistent with sibling validations below)
}

variable "file_path" {
  # typed: resolves via file(); see definition_source_paths
  type        = string
  description = "The filepath to the custom policy. Omitting this assumes the policy is located in the module library"
  default     = null
}

locals {
  # import the custom policy object from a library or specified file path.
  # Resolution is existence-checked so that fully runtime-defined policies
  # (policy_rule/policy_parameters/policy_metadata) remain supported via the
  # "{}" fallback, while a missing definition file with no runtime policy_rule
  # fails loudly with a descriptive error instead of a confusing downstream
  # type error (upstream issue gettek/terraform-azurerm-policy-as-code#11).
  definition_source_paths = [
    var.file_path,
    "${path.cwd}/policies/${title(var.policy_category != null ? var.policy_category : "__unresolved__")}/${var.policy_name != null ? var.policy_name : "__unresolved__"}.json",
    "${path.root}/policies/${title(var.policy_category != null ? var.policy_category : "__unresolved__")}/${var.policy_name != null ? var.policy_name : "__unresolved__"}.json",
    "${path.root}/../policies/${title(var.policy_category != null ? var.policy_category : "__unresolved__")}/${var.policy_name != null ? var.policy_name : "__unresolved__"}.json",
    "${path.module}/../../policies/${title(var.policy_category != null ? var.policy_category : "__unresolved__")}/${var.policy_name != null ? var.policy_name : "__unresolved__"}.json",
  ]

  # try() guards fileexists(null) for callers that omit var.file_path
  # (older Terraform versions do not short-circuit logical operators)
  definition_source_candidates = [
    for path in local.definition_source_paths :
    path if try(fileexists(path), false)
  ]
  definition_source_path = length(local.definition_source_candidates) > 0 ? local.definition_source_candidates[0] : null

  definition_source_resolved = local.definition_source_path != null || var.policy_rule != null

  # the raw JSON text of the resolved definition file:
  # - resolved file      -> file contents
  # - runtime-only       -> "{}" (attributes come from runtime inputs)
  # - neither            -> file() on the embedded-message path raises a
  #                         descriptive missing-file error (outside any try)
  policy_object_json = (
    local.definition_source_resolved ?
    coalesce(local.definition_source_path != null ? file(local.definition_source_path) : null, "{}")
    : file("[ERROR] No policy definition file found for '${var.policy_name != null ? var.policy_name : ""}' in category '${var.policy_category != null ? var.policy_category : ""}'. Provide var.file_path, add the file to the policies library, or supply policy_rule at runtime.")
  )

  policy_object = jsondecode(local.policy_object_json)

  # fallbacks
  title    = title(replace(local.policy_name, "/-|_|\\s/", " "))
  category = coalesce(var.policy_category, try((local.policy_object).properties.metadata.category, "General"))
  version  = coalesce(var.policy_version, try((local.policy_object).properties.metadata.version, "1.0.0"))
  mode     = coalesce(var.policy_mode, try((local.policy_object).properties.mode, "All"))

  # use local library attributes if runtime inputs are omitted
  policy_name  = coalesce(var.policy_name, try((local.policy_object).name, null))
  display_name = coalesce(var.display_name, try((local.policy_object).properties.displayName, local.title))
  description  = coalesce(var.policy_description, try((local.policy_object).properties.description, local.title))
  metadata     = local.metadata_canonical
  parameters   = local.parameters_canonical
  policy_rule  = local.policy_rule_canonical

  # normalize JSON-string inputs to decoded objects so the resource boundary
  # jsonencode() never produces a double-encoded payload (#4)
  metadata_canonical    = try(jsondecode(local.metadata_raw), local.metadata_raw)
  parameters_canonical  = try(jsondecode(local.parameters_raw), local.parameters_raw)
  policy_rule_canonical = try(jsondecode(local.policy_rule_raw), local.policy_rule_raw)

  metadata_raw    = coalesce(null, var.policy_metadata, try((local.policy_object).properties.metadata, merge({ category = local.category }, { version = local.version })))
  parameters_raw  = coalesce(null, var.policy_parameters, try((local.policy_object).properties.parameters, {}))
  policy_rule_raw = coalesce(var.policy_rule, try((local.policy_object).properties.policyRule, null))

  # manually generate the definition Id to prevent "Invalid for_each argument" on set_assignment plan/apply
  # deterministic name suffix: identical inputs (logical name + merged
  # parameter schema + version) always produce the same suffix, so the same
  # logical policy resolves to the same physical Azure Policy definition name
  # across independent state backends; a schema change produces a new suffix
  # and therefore a safe create-before-destroy replacement (#6)
  definition_name_suffix = substr(md5(jsonencode({
    name       = local.policy_name
    parameters = local.parameters
    version    = local.version
  })), 0, 8)

  definition_id = var.management_group_id != null ? "${var.management_group_id}/providers/Microsoft.Authorization/policyDefinitions/${azurerm_policy_definition.def.name}" : azurerm_policy_definition.def.id
}
