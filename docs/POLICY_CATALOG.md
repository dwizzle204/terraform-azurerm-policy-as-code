# Policy Catalog vs Framework

This repository contains two distinct things. Do not confuse them.

## 1. The framework (`modules/`)

The Terraform modules under [`modules/`](../modules) — `definition`, `initiative`,
`set_assignment`, `def_assignment`, `exemption`, `intent` — are the maintained,
tested product. They are covered by CI gates, offline contract tests, a provider
compatibility matrix ([COMPATIBILITY.md](../COMPATIBILITY.md)) and branch
protection. Changes ship through reviewed PRs.

## 2. The bundled policy catalog (`policies/`)

The JSON definitions under [`policies/`](../policies) are **reference/example
content**, not a maintained production baseline:

- Entries were collected over time and include older monitoring, security, DSC
  and baseline patterns that may no longer reflect current Microsoft guidance.
- They exist to demonstrate the modules and to serve as starting points.
- No SLA applies to their correctness, currency, or effect defaults.

Treat any catalog entry you adopt as **your** policy from that point on: review
it against current Microsoft documentation before production use.

## Recommended production model

1. **Prefer Microsoft built-ins** for standard controls. Reference them by
   definition ID list in initiatives; pin built-in versions where your
   assignment strategy requires stable behavior.
2. **Own your custom definitions.** Keep them in *your* repository (or a
   curated catalog repo), versioned and reviewed like code — do not clone this
   repo's full `policies/` tree as a baseline.
3. **Curate explicitly.** Every assignment should trace to an intentional
   control decision (see [GOVERNANCE_INTEGRATION.md](GOVERNANCE_INTEGRATION.md)).
4. If you reuse a bundled example, copy it out, rename it to your convention,
   and remove it from sync considerations.

## Keeping a catalog independent of module releases

Module releases never require catalog changes. Keep your policy content in a
separate repository or directory and consume the modules via pinned source
references (see COMPATIBILITY.md for tested ranges). This lets you upgrade the
framework without re-reviewing hundreds of policy bodies, and vice versa.

Legacy or deprecated entries in `policies/` will eventually be pruned or moved
to an explicit legacy area with migration notes; nothing there is an API.
