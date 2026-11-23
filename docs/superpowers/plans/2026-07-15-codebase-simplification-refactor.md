# Codebase Simplification Refactor — 2026-07-15

Goal: massive, behavior-preserving simplification per AGENTS.md conventions. No feature loss; full suite green after every phase (baseline: 14238 examples, 0 real failures, 66 pending; known flakes under parallel load: `spec/system/responsive_drawer_spec.rb`, auth `passwords_spec.rb` — both pass in isolation).

Surveyed by three parallel explorers (services / MVC / components+views). Lint is already clean (80 trivial RuboCop offenses, ESLint 0). JS already decomposed + 100% Vitest coverage — heavy JS restructuring deliberately out of scope (coverage-maintenance cost, Playwright-only drag engines). Prior gem-boundary decisions honored (OutboundHttp/Faraday, Dentaku, Pagy, Money, dkim, OpenSSL vendor crypto, FormulaCompiler SQL transpiler, code_generators emitted stdlib source).

## Phases (serialized — shared test DB forbids concurrent rspec)

1. **Dead code, components layer** — 23 dead ViewComponents (+ERB+specs, ~3,000 lines), `DesignTokens` concern (+13 includes), `FlowchartMailer` (+views+spec), 8 dead model scopes/helpers (+paired spec blocks), 3 unused ThemeResolver methods. Full suite gate.
2. **Dead code, services layer** — 13 verified-dead services/classes/constants (~600–900 lines): EntityContractFactory, FlowchartApiClient, CalculationEvaluator (ExpressionEvaluator is the live Dentaku wrapper; update Gemfile comment), Billing PauseSubscription, Payments SetDefaultPaymentMethod, Billing::StandardPlans, FlowchartRuntime {TransformApplier, ComputedFieldRegistry, ConfigResolver}, ActivitySteps {RouteParams, PopulateAssociations}, Payments::Errors::AmountMismatch, Email::Errors::DeliveryFailed. All re-verified by main session (exact-class + snake_case dynamic-dispatch grep).
3. **Controller clone consolidation** — BaseRestorationsController (entity/flowchart/customer); platform emails/sms credentials controllers → shared base (characterization request specs written FIRST — none exist today); `Authentication::User` recovery trio → one `scoped_recovery` helper.
4. **Services consolidation** — parameterized PluginRegistry for the 4 identical vendor registries (~130 lines); shared daily-cap helper (sms/email Send); shared vendor plugin base (sms/email/captcha `base.rb`, careful: i18n prefix, init kwarg, label fallback differ); `handle_webhook.rb` `finalize_success!` extraction (pure extraction; 901-line spec guards it).
5. **View retrofits** — 19 admin views onto existing `AdminPageComponent`, 8 views onto `EmptyStateComponent`; `.card-header` (49×) + `.form-actions` (~30×) shortcuts in `@layer components`; optional PanelComponent for the 47× titled-card pattern. Tailwind rebuild.
6. **Table-shell consolidation** — 9 bespoke `*_table_component`s onto `AdminTableComponent`/shared shell; highest per-file risk, one at a time.
7. **Final** — `rubocop -a` (80 trivial), full parallel suite, tailwind rebuild, vitest untouched (no JS changes planned).

## Phase 6 (added on user direction: "no hand-rolled allowed") — library swaps
Evidence gathered 2026-07-15 from RubyGems: stripe 19.3.0 (2026-06, 116M dl) and twilio-ruby 7.10.7 (2026-05, 129M dl) are mature official gems → Stripe gateway + Twilio adapter internals swapped onto them (public gateway/adapter APIs unchanged, per-tenant client instantiation, webhook verification via gem validators). paypal-server-sdk 2.3.0 (official, 2026-06) adopted for covered endpoints; uncovered ones stay on REST with an SDK-gap comment. FormulaCompiler's hand-rolled tokenizer/parser replaced by Dentaku's public AST API + app-side SQL-emission visitor (byte-identical SQL, differential-verified; no gem anywhere does formula→SQL). USER-CONFIRMED KEPT on stdlib OpenSSL with in-code justification: Alipay (only gem: unofficial, last release 2023-07), WeChat Pay v3 (only gem: 2021-07, singleton config), Aliyun SMS/captcha (no Ruby SDK exists at all — Alibaba never shipped one; aliyun-sdk is OSS-storage only).

## Explicitly de-scoped (assessed, justified complexity — do NOT touch)
- `theme_resolver.rb` color tables (Tailwind content scanner needs literal class strings)
- `payments/checkouts_controller.rb` (per-action security rationale), `dynamic_controller.rb`, `tenant_context.rb`, `versionable.rb`, `bridge_entity_management.rb`, `entity.rb`, `authentication/user.rb` (core domain)
- `activity_generator.rb`, `page_content_generator.rb`, `flowchart_topology_analyzer.rb`, `activity_tracer.rb` (read in full — table-driven/delegating, not spaghetti)
- email vs SMS credential form *components* (intentionally divergent after five-module redo — false clone lead; the *controllers* are still true clones)
- All JS monolith restructuring; drag engines; code_generators.
