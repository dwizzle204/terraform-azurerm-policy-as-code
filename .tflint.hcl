# TFLint configuration for terraform-azurerm-policy-as-code
# Uses the bundled terraform ruleset (deterministic, no plugin downloads).
# For provider deep-checks locally, optionally add:
#   plugin "azurerm" { enabled = true }
#   plugin "azuread" { enabled = true }
# and run `tflint --init`.
plugin "terraform" {
  enabled = true
  preset  = recommended
}

rule "terraform_required_version" {
  enabled = false # modules intentionally declare loose floors
}

rule "terraform_unused_required_providers" {
  enabled = false # azuread is consumed via resources in assignment modules
}
