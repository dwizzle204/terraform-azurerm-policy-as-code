# LIVE Azure Integration Tests

Optional live-Azure suite for behavior that mocked provider tests cannot prove
(see issue #16). These tests are **not** part of normal PR validation.

## What belongs here

Only tests that require real ARM API behavior:

- ARM / Azure Policy API acceptance of definition payloads (covered by the current skeleton)
- ARM / Azure Policy API acceptance of assignment and remediation payloads (requires disposable dependent fixtures, e.g. a Log Analytics workspace — extend before adding)
- Managed identity and RBAC propagation timing
- Actual remediation task execution
- Provider regressions that only appear against live Azure

## Prerequisites

- A **disposable** Azure subscription (never shared or production)
- Contributor + User Access Administrator on that subscription
- Terraform >= 1.7

## Running

```bash
cd integration-tests/azure
export ARM_SUBSCRIPTION_ID="<disposable-subscription-id>"
export ARM_TENANT_ID="..."
export ARM_CLIENT_ID="..."
export ARM_CLIENT_SECRET="..."
terraform init
terraform test -var="test_subscription_id=$ARM_SUBSCRIPTION_ID"
```

Note: `ARM_SUBSCRIPTION_ID` is not auto-wired to the `test_subscription_id`
input variable — pass it explicitly with `-var` as shown above.

## Hygiene

- Always `terraform destroy` after a run (`terraform destroy -var test_subscription_id=...`)
- Never commit credentials or subscription IDs
- These tests are intentionally excluded from `.github/workflows/tests.yml`
