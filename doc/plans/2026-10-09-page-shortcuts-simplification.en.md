# Page shortcut implementation review and simplification

## Goal

Preserve existing shortcut URLs, tenant selection, publication checks, native management forms, canonical submissions, captcha protection and bounded public-link queries while reducing duplicated source logic.

## Implementation plan

1. Reuse the resolver's request cache and remove redundant customer-prefixed glob routes; retain fixed controller destinations and explicit root handling.
2. Dispatch website aliases by the resolved record ID, rather than looking up the resolved slug again.
3. Reuse the scalar presentation lookup for management labels and availability instead of loading Page definitions or duplicating component eligibility rules.
4. Serialize shortcut and website-page validation/persistence with the same customer row lock. Reload persisted shortcuts before building their contracts to apply explicitly submitted fields against current data.
5. Add regression coverage for identity reuse, stale writes, collision serialization, unavailable mappings and bounded management queries; make feature fixtures independent of seeded modules.
6. Update English and Simplified Chinese developer references, run affected specs, and review correctness and project conventions.

## Acceptance

- Existing host/prefix precedence, GET/HEAD/public-Page POST behavior and terminal root 404s remain intact.
- Tenant guards and shared-page resolution remain authoritative.
- Management retains saved unavailable identities, localized labels and field errors.
- Public-link and management query counts remain bounded as destinations increase; management does not load Page definitions.
- Concurrent edits cannot silently discard explicit shortcut values or validate collisions outside the shared write boundary.
