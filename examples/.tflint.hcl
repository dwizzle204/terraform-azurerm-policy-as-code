# Nested tflint config for the examples directory.
# Examples intentionally declare ready-to-use data sources that may not be
# referenced by every sample file, so unused-declaration noise is disabled.
plugin "terraform" {
  enabled = true
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
  version = "0.15.0"
  preset  = "recommended"
}

rule "terraform_unused_declarations" {
  enabled = false
}
