# Email Module — Professional ESP Refactor Roadmap

> **For agentic workers:** This is the master roadmap. Implement each phase via its linked plan. REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` or `superpowers:executing-plans`.

**Goal:** Transform the existing Email module into an industry-standard ESP experience with reorganized navigation, message streams, audience management, campaign builder, automations, analytics, and preference center.

**Architecture:** Build on the existing multi-tenant Rails foundation. Introduce `Emails::Stream` as the central routing/tracking/throttle classifier. Move `EmailCampaigns` into `Emails::Campaigns` and `Emails::Audience`. Add new subsystems (segments, tags, assets, automations, preference topics) as isolated namespaces. Deliver in sequential phases so each phase is independently shippable and testable.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, TailwindCSS, StimulusJS, ViewComponent, RSpec, Trailblazer/Reform/dry-rb, Active Storage (asset library).

## Global Constraints

- All user-facing strings must be I18n in `en` and `zh-CN`; no hard-coded copy.
- All styling uses TailwindCSS only; no custom CSS.
- All JavaScript uses StimulusJS only; no custom JS frameworks.
- Admin routes require `admin` or `owner`; public endpoints are token/signature-scoped.
- Cross-tenant scoping via `TenantScoped` / `for_current_customer` on every record action.
- Changes made directly on `master`; do not auto-commit.
- Run targeted specs per phase; run full suite only before declaring the whole refactor complete.

---

## Phase Overview

| Phase | Focus | Key Deliverables | Plan File |
|---|---|---|---|
| 1 | Foundation | Message streams, sidebar restructure, namespace cleanup (`EmailCampaigns` → `Emails::*`) | [Phase 1 Plan](2026-07-20-email-module-phase1-foundation.md) |
| 2 | Audience | Contacts, tags, segments, lists refactor, signup forms | [Phase 2 Plan](2026-07-20-email-module-phase2-audience.md) |
| 3 | Content | Template categories, asset library, template enhancements | [Phase 3 Plan](2026-07-20-email-module-phase3-content.md) |
| 4 | Campaigns | Wizard builder, A/B testing, campaign delivery updates | [Phase 4 Plan](2026-07-20-email-module-phase4-campaigns.md) |
| 5 | Automations | Workflow definitions, triggers, step execution | [Phase 5 Plan](2026-07-20-email-module-phase5-automations.md) |
| 6 | Analytics | Reports, deliverability dashboard, engagement, CSV export | [Phase 6 Plan](2026-07-20-email-module-phase6-analytics.md) |
| 7 | Settings | Streams UI, suppressions UI, preference center/topics | [Phase 7 Plan](2026-07-20-email-module-phase7-settings.md) |

## Cross-Cutting Rules

1. **URL stability:** Public unsubscribe (`/unsubscribe/:token`), tracking (`/email/track/*`), and webhook (`/email/webhooks/:provider`) paths must never change.
2. **Database compatibility:** No table drops. Namespace moves keep existing table names via `self.table_name`.
3. **Phase 1 is a hard dependency** for all later phases. Phases 2–7 can be developed in parallel only after Phase 1 is merged.
4. **I18n parity:** Every new key added in a phase must have matching `en` and `zh-CN` entries before the phase is considered complete.
5. **Test coverage:** Each phase adds model/service/job/request/component specs for its changes and runs the existing email spec suite to guard regressions.

## Rollout Order

1. Merge Phase 1 and run full email spec suite.
2. Merge Phase 2.
3. Merge Phases 3–7 in order; Phases 3 and 4 may be parallel after Phase 2.
4. Run full suite once after the final phase.
