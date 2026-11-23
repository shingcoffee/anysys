# Email Module UI/UX Refactor & Phase 2 Simplification Design

## Purpose
The goal of this refactoring is to drastically simplify the Email module navigation for customers and elevate the visual aesthetics of all metrics, charts, and pages to a premium, modern SaaS standard. 

Following the user's decision, we will consolidate the navigation into exactly four main top-level sidebar items (Overview, Campaigns, Audience, and Settings), while adding stunning gradient-filled SVG trend lines and interactive metric cards.

## Approach & Scope

### 1. Navigation & Sidebar Simplification (4 Top-Level Sections)
The `FeatureModules::Email::Registration` class will return exactly four sidebar entries:
1.  **Overview** (`/emails/dashboard`): Consolidates Dashboard and Analytics.
    *   **In-Page Tabs**: `Dashboard` | `Reports` | `Deliverability` | `Engagement`
2.  **Campaigns** (`/emails/campaigns` or `/emails/automations` if campaigns disabled): Consolidates Campaigns, Automations, and Templates.
    *   **In-Page Tabs**: `Campaigns` | `Automations` | `Templates`
3.  **Audience** (`/emails/contacts`): Holds all contact-related lists and block lists.
    *   **In-Page Tabs**: `Contacts` | `Lists` (if campaigns enabled) | `Segments` | `Tags` | `Signup Forms` | `Block-List` (if campaigns enabled)
4.  **Settings** (`/emails/streams`): Holds stream-level preferences and suppressions.
    *   **In-Page Tabs**: `Streams` | `Suppressions` | `Preference Topics`

All pages under each of the sections will render a shared horizontal in-page tabs component. Each page will logically align its breadcrumbs and top-level title to the corresponding main section (e.g. "Overview" or "Campaigns") with the tab showing the sub-context, making the user experience seamless.

### 2. Premium Visual Enhancements
We will implement high-fidelity visual upgrades using custom Tailwind CSS classes and precise SVG elements:
*   **Interactive Stat Cards**: 
    *   Stat cards will lift and shadow-glow on hover: `hover:shadow-md transition-all duration-200 transform hover:-translate-y-0.5`.
    *   Each metric will have a signature left-accent border bar (4px) to make the page visually scan-friendly:
        *   **Sent**: Indigo (`border-l-4 border-l-indigo-500`)
        *   **Delivered**: Green (`border-l-4 border-l-emerald-500`)
        *   **Bounced**: Rose (`border-l-4 border-l-rose-500`)
        *   **Complained**: Orange (`border-l-4 border-l-orange-500`)
        *   **Suppressed**: Yellow (`border-l-4 border-l-amber-500`)
        *   **Opened**: Sky Blue (`border-l-4 border-l-sky-500`)
        *   **Clicked**: Pink (`border-l-4 border-l-pink-500`)
        *   **Unsubscribed**: Violet (`border-l-4 border-l-violet-500`)
*   **Trend Chart Area Gradients (Gradients Under Lines)**:
    *   Instead of flat, thin lines, charts on the Dashboard and reports Sparkline lines will feature a beautiful transparent area gradient underneath, fading to opacity `0` at the bottom of the SVG viewport.
    *   This is achieved by rendering an SVG `<polygon>` using the same x/y coordinate sequence bounded at the bottom boundary `(x_i, height)` and using an SVG `<linearGradient>` with custom stops.
    *   All SVGs will use `stroke-linecap="round" stroke-linejoin="round"` for high-fidelity rendering.
*   **Consistent Component Styling**:
    *   Date range picker and tables will be wrapped in polished cards with fine, crisp borders (`border-zinc-200 dark:border-zinc-700`).

### 3. Localization (I18n Rule Compliance)
All labels, headings, buttons, tab titles, tooltips, and empty-state placeholders must be fully localized with NO hard-coded literal strings. We will update English (`en`) and Simplified Chinese (`zh-CN`) translations under `config/locales/` to align with the new 4-item design and visual elements.

## Implementation Steps
1.  **Locales Update**: Update `config/locales/feature_modules.en.yml` and `config/locales/feature_modules.zh-CN.yml` to define the simplified sidebar names, breadcrumbs, and tab names.
2.  **Sidebar Registration**: Modify `app/services/feature_modules/email/registration.rb` to return the new 4-item layout.
3.  **Horizontal Tab Partials**:
    *   Create `/shared/_overview_tabs.html.erb` with Dashboard, Reports, Deliverability, and Engagement.
    *   Create `/shared/_campaigns_tabs.html.erb` with Campaigns (if enabled), Automations, and Templates.
4.  **Redesign Views**:
    *   **Dashboard** (`dashboard/show.html.erb`): Integrate `_overview_tabs`. Refactor stat cards to have left-color accent borders and hover lift effects. Redesign the daily trend charts to use `<linearGradient>` filled area polygon overlays.
    *   **Sparkline Component** (`Emails::SparklineComponent`): Redesign to render an area gradient under the sparkline polyline.
    *   **Reports/Analytics** (`ReportsComponent`, `DeliverabilityComponent`, `EngagementComponent`): Inject correct tabs, adjust titles/breadcrumbs to "Overview", and update metrics card layout and color accents.
    *   **Campaigns & Templates**: Adjust titles/breadcrumbs to "Campaigns" and render the correct campaigns tabs.
5.  **Validation**: Run all relevant RSpec request specs and verify they pass. Ensure no I18n strings are missing.

## Out of Scope
*   Adding new database migrations, models, or core business logic.
*   Modifying non-email admin/member layouts or routes.

