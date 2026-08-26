# LIVE Azure integration test — NOT part of normal PR validation.
# Requires ARM_SUBSCRIPTION_ID / ARM_TENANT_ID / ARM_CLIENT_ID / ARM_CLIENT_SECRET
# against a disposable subscription. Run manually:
#   cd integration-tests/azure && terraform test

run "live_definition_and_assignment_apply" {
  command = apply

  assert {
    condition     = can(regex("^/subscriptions/", module.assignment_live.id))
    error_message = "Live assignment should return an Azure resource id"
  }
}
