# Email Module Visual Polish — AdminPage Consistency (no Figma)

**Source of truth:** existing AdminPage / AdminTable / `card` / `btn` / design tokens (`text-text-*`, `border-border`, `text-primary`/`text-accent`, `bg-surface-*`).

## Surfaces to polish

1. **Emails::TabsComponent** — active tab: `border-primary text-primary`; inactive: `border-transparent text-text-muted hover:text-text-primary hover:border-border`; container `border-border` (not zinc/indigo).

2. **Emails::MetricCardComponent** (new) — single KPI card used by Overview + Health:
   - Wrapper: `card p-4 border-l-4` + accent border class prop
   - Label: `text-sm font-medium text-text-muted`
   - Value: `text-2xl font-semibold text-text-primary`
   - Optional subtle hover: `hover:shadow-md transition-base` (match admin, not unique motion language)
   - Replace duplicated zinc/indigo card markup in dashboard + health (+ dead reports/deliverability/engagement templates if still rendered)

3. **Campaign wizard stepper** (`campaign_builder_component.html.erb`):
   - Replace `text-gray-*` / `text-blue-*` with `text-text-muted` / `text-primary`
   - Connector borders: `border-border`
   - Step title: `text-text-primary`
   - Keep `card` + `btn btn-primary/secondary`

4. **Suppressions bulk toolbar**:
   - Place All + Unblock inside the same visual chrome as the table: wrap form+table in `card overflow-hidden`, toolbar row `px-4 py-3 border-b border-border-subtle flex …`, then AdminTable without double card if possible — OR keep AdminTable card and put toolbar as `mb-0` adjacent top bar with `card mb-0 rounded-b-none` / table `rounded-t-none` only if low risk
   - Prefer: toolbar as first row inside a wrapping `space-y-0` card; if AdminTable always renders its own card, use `class="mb-3 flex … p-3 card"` matching spacing of other admin toolbars

5. **Campaign show** — already AdminPage + LandingStatsCard; replace hard-coded `—` with `t("common.labels.none")` or existing dash key if present (`common.punctuation.em_dash` / search first). Keep tokens.

6. **Out of scope:** template composer deep redesign, new fonts/colors, Email page shell.

## Component reuse
- AdminPageComponent, AdminTableComponent, LandingStatsCardComponent (campaign show metrics), Emails::TabsComponent, Emails::DateRangePickerComponent, btn/card utilities
