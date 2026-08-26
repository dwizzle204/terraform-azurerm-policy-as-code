# LIVE Azure integration test — NOT part of normal PR validation.
# Requires ARM_SUBSCRIPTION_ID / ARM_TENANT_ID / ARM_CLIENT_ID / ARM_CLIENT_SECRET
# against a disposable subscription. Run manually:
#   cd integration-tests/azure && terraform init && \
#   terraform test -var="test_subscription_id=$ARM_SUBSCRIPTION_ID"

run "live_definition_apply" {
  command = apply

  assert {
    condition     = can(regex("^/subscriptions/[^/]+/providers/Microsoft.Authorization/policyDefinitions/", module.definition_live.id))
    error_message = "Live definition should return a subscription-scoped Azure policyDefinitions resource id"
  }

  assert {
    condition     = jsondecode(module.definition_live.metadata).category == "Monitoring"
    error_message = "Live definition metadata should carry the library category"
  }
}
