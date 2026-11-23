# Product Requirements Brief: Member UI Visual Refactor

**Date:** 2026-05-26  
**Type:** UI Refactor (Layout + Styling Only)  
**Scope:** Member portal (`/:cid/member/*`) + Member auth flows (`/:cid/auth/*`)  
**Goal:** Make the member-facing surfaces more beautiful: warmer, more modern, more polished, with a stronger sense of design craft

---

## 1. Vision Statement

Members of this platform — donors, members, customers-of-customers — arrive with expectations shaped by the consumer web (Stripe billing portals, Notion workspaces, Linear dashboards). Today's member portal is functional but utilitarian. This refactor elevates it to feel **inviting, confident, and effortless**: a place members want to return to. "More beautiful" means: refined visual hierarchy, generous white space, considered color use (not corporate gray), subtle motion that feels alive (not static), responsive layouts that adapt gracefully from mobile to desktop, and polish in every state (loading, empty, error, success). The result should feel warm and human, not sterile; modern and fresh, not trendy; professional and trustworthy, not casual.

---

## 2. Personas

**Primary persona: The Member (Member / Donor / Customer-of-customer)**

- **Context:** Self-signed-up user managing their own profile, payments, and security
- **Device:** Primarily mobile (60% traffic), occasionally desktop for longer tasks (profile updates, payment history review)
- **Mood on arrival:** Task-oriented (sign in, update card, check MFA status) but easily frustrated by clutter or confusion; delighted by clarity and polish
- **Technical comfort:** Medium; expects autofill, clear error messages, forgiving forms; does not read help text unless stuck
- **Access frequency:** Infrequent — quarterly for payment updates, annually for profile changes, immediately after receiving an email prompt (password reset, MFA recovery)
- **Trust requirement:** High — this portal holds payment methods and account security; visual polish signals competence

**Edge persona: The Admin checking the member view**

- **Context:** Customer admin previewing how their members will see the portal
- **Device:** Desktop
- **Mood:** Evaluative; comparing against their own admin interface; looking for brand consistency and member-friendly design
- **Not the optimization target** — but a beneficiary of clarity and polish

---

## 3. User Stories

### US-1: Sign-in experience
**As a member**, I want the sign-in page to feel welcoming and trustworthy, so that I feel confident entering my credentials and returning in the future.

**Acceptance criteria:**
- The split-pane auth shell (brand panel + form) establishes a clear visual hierarchy with the form side receiving primary focus
- The brand panel on desktop uses color, imagery, or gradient to create warmth; on mobile it collapses to a slim header that does not compete with the form
- Input fields are visually distinct from background, with clear focus states and accessible contrast (WCAG AA)
- Error messages appear inline near the relevant field with a warm danger tone (not alarming red)
- The "Sign in" button is visually weighted as the primary action

### US-2: Dashboard arrival
**As a member**, I want the dashboard to greet me clearly and show my account status at a glance, so that I can quickly decide what to do next.

**Acceptance criteria:**
- The hero greeting uses a larger, warmer typographic scale that feels personal (not corporate)
- Status cards (Profile, Payments, Security) use visual tone (color, icon, badge) to communicate state (complete, active, warning) without requiring text parsing
- Empty state ("Welcome — your activity will show up here") feels encouraging, not barren
- The page layout breathes: generous vertical spacing between sections, no cramped rows

### US-3: Profile management
**As a member**, I want the profile view and edit pages to feel calm and organized, so that I can update my information without cognitive overload.

**Acceptance criteria:**
- The page header clearly separates page title, description, and primary action (Edit / Save) with typographic hierarchy
- Form fields in edit mode use a consistent visual rhythm (label above, input below, help text if needed, error inline)
- Read-only detail grids (profile show) use subtle borders and spacing to group related fields without visual noise
- Long email addresses or names do not break layout on mobile; text truncates gracefully with ellipsis and full text accessible via focus or tap

### US-4: Security / MFA flows
**As a member**, I want MFA setup, challenge, and recovery flows to feel guided and reassuring, so that I can complete security actions without anxiety.

**Acceptance criteria:**
- Each step in the MFA setup flow (QR scan, verification) uses clear visual progression cues (step numbers or progress indicators)
- The QR code is centered, adequately sized, and surrounded by white space for easy scanning
- Success states (MFA enabled, recovery code saved) use positive visual tone (green accent, checkmark icon) that feels celebratory, not clinical
- Recovery code display uses a monospace font and clear "Copy" affordance

### US-5: Surface index (module entries)
**As a member**, I want the list of my entries (payments, forms, etc.) to feel scannable and actionable, so that I can find what I need and act on it quickly.

**Acceptance criteria:**
- The index table uses alternating row shading or subtle dividers to improve scannability
- Column headers are visually distinct from data rows
- Empty state when no entries exist feels encouraging ("Get started by...") with a clear primary action
- Pagination controls are unobtrusive but discoverable, with clear "previous / next" affordances

### US-6: Surface detail (single entry)
**As a member**, I want the detail view of a single entry to present information clearly, so that I can understand the record without hunting for key facts.

**Acceptance criteria:**
- The detail grid groups related fields into labeled sections with subtle visual separation
- Key-value pairs use adequate spacing; keys are secondary weight, values are primary
- CTAs (Download, Cancel, etc.) are grouped and visually weighted by importance (primary vs. secondary button styles)
- Long values (e.g., payment gateway reference IDs) wrap or truncate without breaking the grid

### US-7: Mobile navigation
**As a member on mobile**, I want the navigation to be accessible without obscuring content, so that I can move between sections effortlessly.

**Acceptance criteria:**
- The top nav collapses to a hamburger menu on mobile with a smooth slide-in animation
- The mobile sheet lists nav items vertically with touch-friendly tap targets (min 44px height)
- The sheet closes when a nav item is tapped or when the user taps outside
- The nav feels lightweight — no heavy shadows or borders that compete with page content

### US-8: Responsive layout adaptation
**As a member switching between devices**, I want every page to adapt gracefully to my screen size, so that I never encounter broken layouts or horizontal scroll.

**Acceptance criteria:**
- All member pages are fully responsive: mobile (320px+), tablet (768px+), desktop (1024px+)
- Status cards on the dashboard stack vertically on mobile, display in a 2-column grid on tablet, and a 3-column grid on desktop
- Forms use single-column layout on mobile; two-column on desktop where appropriate (e.g., first name / last name side-by-side)
- The auth shell's split-pane collapses to single-column on mobile with the brand panel as a slim header

### US-9: Loading and error states
**As a member**, I want loading and error states to feel polished, so that I understand what is happening and what to do next.

**Acceptance criteria:**
- Loading states use a subtle spinner or skeleton UI (not a blank screen)
- Error messages are inline, contextual, and written in plain language (not technical jargon)
- Network errors (gateway down, timeout) surface a friendly "Something went wrong" message with a retry CTA
- Empty states across all surfaces (no payments, no activity, no entries) feel warm and actionable, not barren

### US-10: Visual cohesion across surfaces
**As a member navigating the portal**, I want every page to feel like part of the same system, so that I build familiarity and trust.

**Acceptance criteria:**
- All member pages share a consistent typographic scale (heading sizes, body text, labels)
- Button styles (primary, secondary, danger) are visually consistent across all surfaces
- Color usage (accent, success, warning, danger) is semantically consistent (green always means success, etc.)
- Spacing rhythm (padding, margins, gaps) follows a consistent scale (e.g., 4px, 8px, 16px, 24px, 32px)

---

## 4. Acceptance Criteria for the Refactor as a Whole

1. **Visual cohesion:** All member pages share a consistent design language — typography, color, spacing, button styles — such that a member perceives a unified system, not a patchwork
2. **Responsive behavior:** Every page is fully functional and visually polished on mobile (320px+), tablet (768px+), and desktop (1024px+); no horizontal scroll, no broken layouts, no obscured content
3. **Accessibility:** All interactive elements meet WCAG 2.1 AA standards: focus states are visible, color contrast ratios are ≥4.5:1 for body text and ≥3:1 for large text, form labels are programmatically associated, error messages are announced to screen readers
4. **Motion and transitions:** Micro-interactions (button hover, menu slide-in, focus ring) use subtle, purposeful motion (150-300ms transitions) that feels alive; no jarring snaps or excessive animation
5. **Dark mode posture:** Out of scope for this refactor — member pages remain light-mode only; no dark-mode toggle or theme switching
6. **Empty, loading, and error state polish:** Every list, every form, every async action has a designed empty/loading/error state that feels intentional and helpful (not an afterthought)
7. **Brand temperature:** The visual tone is warm and human (not sterile corporate): softer color palette, rounded corners, subtle shadows, inviting hero sections, encouraging empty states
8. **Performance:** No new external assets larger than 50KB total; no new JavaScript bundles; no Google Fonts beyond Inter (already loaded); existing Turbo + Stimulus behavior is preserved; no regression in page load times
9. **Component encapsulation:** All visual changes are encapsulated in ViewComponents (under `app/components/member/*`) or view templates; no global CSS pollution that affects admin surfaces
10. **Multi-tenant safety:** No visual or layout changes alter customer scoping (`customer_id` filtering); all authorization guards remain intact; this is purely a presentation-layer refactor

---

## 5. Edge Cases to Handle

- **Long names or emails:** Member's full name is 80+ characters (e.g., internationalized names); email is 60+ characters. Layout must not break; text truncates gracefully with ellipsis and full value accessible via hover/focus or a separate line on mobile.
- **Member with no surfaces enabled:** Dashboard shows no module cards (e.g., Payments disabled, no custom surfaces). Empty state must feel welcoming ("Your dashboard will show available features here") and not broken.
- **Member with 50+ surface entries:** Index table with pagination must remain performant and scannable; no layout thrash from long field values.
- **RTL (right-to-left) locales:** Out of scope for this refactor — LTR (left-to-right) only.
- **Slow connections:** Loading states must appear within 200ms; skeleton UI or spinner must be visible on 3G connections; no flash of unstyled content (FOUC).
- **Screen reader walkthrough:** A screen-reader user must be able to navigate the entire member portal using only keyboard and hear logical, contextual announcements (field labels, error messages, success confirmations, nav structure).
- **Very short viewport (mobile landscape, iPhone SE):** Sticky top nav must not obscure page content; scroll behavior must feel natural.
- **Concurrent updates (optimistic locking edge case):** If two members somehow share an account and update the profile simultaneously, the error message ("Profile was updated by another session; please reload") must be inline and clear — but this is a backend concern; the UI just needs to surface it gracefully.
- **Browser compatibility:** Modern evergreen browsers only (Chrome, Safari, Firefox, Edge — last 2 versions); no IE11 support required.

---

## 6. Out of Scope (Explicitly)

- **Admin pages:** All surfaces under `/:cid/admin/*` retain their current design; no changes to admin layout, admin components, or admin design tokens
- **Business logic changes:** No changes to controllers, models, contracts, activities, mailers, or routes; this is a presentation-layer-only refactor
- **New member features:** No new pages, no new sections, no new capabilities (e.g., no payment method management if not already present, no new dashboard widgets)
- **Dark mode:** Light mode only; no dark-mode toggle or theme switching in this refactor
- **Internationalization (i18n):** English-language UI only; no new translation keys, no RTL layout support
- **New external dependencies:** No new gems, no new npm packages, no new icon libraries beyond what Heroicons already provides (if present), no new fonts beyond Inter
- **Email templates:** Mailer views (password reset email, MFA recovery email) are out of scope; this refactor touches only web UI
- **Performance optimization beyond asset hygiene:** No code splitting, no lazy loading of images, no service-worker caching — just "don't add bloat"
- **Backend authorization or scoping changes:** All role checks, `customer_id` scoping, and `user_id` ownership guards remain exactly as they are
- **Cross-customer access or platform-owner surfaces:** This refactor touches only member-facing pages; no changes to `/:cid/maintenance/*` or cross-tenant admin surfaces

---

## 7. Non-Functional Constraints

- **CSS framework:** TailwindCSS only; no custom CSS files, no other CSS frameworks (per AGENTS.md)
- **JavaScript framework:** StimulusJS only for interactivity (mobile nav toggle, user menu dropdown, flash auto-dismiss); no custom JavaScript, no React/Vue/Alpine (per AGENTS.md)
- **ViewComponent encapsulation:** All visual changes must be encapsulated in ViewComponents under `app/components/member/*`; no global style changes that leak into admin surfaces
- **Multi-tenant scoping:** Every page must continue to respect `customer_id` scoping; no visual change may alter or bypass tenant isolation
- **Asset size budget:** Total new external assets (images, fonts, icons) must not exceed 50KB; Inter font is already loaded from `rsms.me/inter/inter.css` (no additional font files)
- **No new Google Fonts:** Inter is already in use; do not add additional font families
- **Browser compatibility:** Modern evergreen browsers only (Chrome, Safari, Firefox, Edge — last 2 versions); no polyfills, no IE11 support
- **Responsive breakpoints:** Follow Tailwind's default breakpoints: `sm: 640px`, `md: 768px`, `lg: 1024px`, `xl: 1280px`, `2xl: 1536px`
- **Accessibility target:** WCAG 2.1 Level AA compliance for all interactive elements (focus states, contrast, keyboard navigation, screen-reader labels)
- **Motion preference:** Respect `prefers-reduced-motion` media query; users who enable this system setting must see no animation (transitions instant or disabled)
- **No breaking changes to existing behavior:** All Turbo navigation, Stimulus controllers, form submissions, and flash messages must continue to work exactly as before; this is a visual refactor, not a behavioral refactor

---

## 8. Design Deliverables Expected from UX Designer

The UX designer (frontend-design plugin) will produce:

1. **Design system tokens:** Color palette (primary, accent, success, warning, danger, surface, border, text shades), typographic scale (font sizes, line heights, weights), spacing scale, shadow scale, border-radius values
2. **Component redesigns:** Visual specs for each of the 14 member components (ShellComponent, AuthShellComponent, TopNavComponent, UserMenuComponent, PageHeaderComponent, PageSectionComponent, HeroCardComponent, StatusCardComponent, DetailGridComponent, IndexTableComponent, SurfaceIndexComponent, SurfaceDetailComponent, EmptyStateComponent, PaginationComponent)
3. **Layout refinements:** Specs for the two member layouts (`member.html.erb`, `auth.html.erb`) including container widths, nav structure, and shell chrome
4. **State variations:** Visual specs for hover, focus, active, disabled, loading, error, empty states across all interactive elements
5. **Responsive behavior:** Breakpoint-specific layout adjustments for mobile, tablet, and desktop
6. **Motion guidelines:** Transition durations, easing curves, and `prefers-reduced-motion` fallbacks

The design system tokens will be applied as Tailwind utility classes or custom Tailwind config extensions (e.g., `theme.extend.colors` for member-specific colors).

---

## 9. Open Questions (None at This Time)

All necessary context is provided. The UX designer has freedom within the constraints above to define the visual language. Brainstorming may raise questions about specific design decisions (e.g., "Should the hero card use a gradient or a solid color?"), but those are design choices, not requirements gaps.

---

## RETURN

**problem_statement:** Members of this platform arrive with expectations shaped by the consumer web and deserve a portal that feels warm, modern, and polished. Today's member-facing pages are functional but utilitarian. This refactor elevates the visual design — layout, typography, color, spacing, motion — to create an inviting, confident, effortless experience that members want to return to. This is a UI-only refactor: no new features, no backend changes, no route changes.

**user_stories:**
  - As a member, I want the sign-in page to feel welcoming and trustworthy, so that I feel confident entering my credentials and returning in the future.
  - As a member, I want the dashboard to greet me clearly and show my account status at a glance, so that I can quickly decide what to do next.
  - As a member, I want the profile view and edit pages to feel calm and organized, so that I can update my information without cognitive overload.
  - As a member, I want MFA setup, challenge, and recovery flows to feel guided and reassuring, so that I can complete security actions without anxiety.
  - As a member, I want the list of my entries (payments, forms, etc.) to feel scannable and actionable, so that I can find what I need and act on it quickly.
  - As a member, I want the detail view of a single entry to present information clearly, so that I can understand the record without hunting for key facts.
  - As a member on mobile, I want the navigation to be accessible without obscuring content, so that I can move between sections effortlessly.
  - As a member switching between devices, I want every page to adapt gracefully to my screen size, so that I never encounter broken layouts or horizontal scroll.
  - As a member, I want loading and error states to feel polished, so that I understand what is happening and what to do next.
  - As a member navigating the portal, I want every page to feel like part of the same system, so that I build familiarity and trust.

**acceptance_criteria:**
  story_1:
    - The split-pane auth shell (brand panel + form) establishes a clear visual hierarchy with the form side receiving primary focus
    - The brand panel on desktop uses color, imagery, or gradient to create warmth; on mobile it collapses to a slim header that does not compete with the form
    - Input fields are visually distinct from background, with clear focus states and accessible contrast (WCAG AA)
    - Error messages appear inline near the relevant field with a warm danger tone (not alarming red)
    - The "Sign in" button is visually weighted as the primary action
  story_2:
    - The hero greeting uses a larger, warmer typographic scale that feels personal (not corporate)
    - Status cards (Profile, Payments, Security) use visual tone (color, icon, badge) to communicate state (complete, active, warning) without requiring text parsing
    - Empty state ("Welcome — your activity will show up here") feels encouraging, not barren
    - The page layout breathes: generous vertical spacing between sections, no cramped rows
  story_3:
    - The page header clearly separates page title, description, and primary action (Edit / Save) with typographic hierarchy
    - Form fields in edit mode use a consistent visual rhythm (label above, input below, help text if needed, error inline)
    - Read-only detail grids (profile show) use subtle borders and spacing to group related fields without visual noise
    - Long email addresses or names do not break layout on mobile; text truncates gracefully with ellipsis and full text accessible via focus or tap
  story_4:
    - Each step in the MFA setup flow (QR scan, verification) uses clear visual progression cues (step numbers or progress indicators)
    - The QR code is centered, adequately sized, and surrounded by white space for easy scanning
    - Success states (MFA enabled, recovery code saved) use positive visual tone (green accent, checkmark icon) that feels celebratory, not clinical
    - Recovery code display uses a monospace font and clear "Copy" affordance
  story_5:
    - The index table uses alternating row shading or subtle dividers to improve scannability
    - Column headers are visually distinct from data rows
    - Empty state when no entries exist feels encouraging ("Get started by...") with a clear primary action
    - Pagination controls are unobtrusive but discoverable, with clear "previous / next" affordances
  story_6:
    - The detail grid groups related fields into labeled sections with subtle visual separation
    - Key-value pairs use adequate spacing; keys are secondary weight, values are primary
    - CTAs (Download, Cancel, etc.) are grouped and visually weighted by importance (primary vs. secondary button styles)
    - Long values (e.g., payment gateway reference IDs) wrap or truncate without breaking the grid
  story_7:
    - The top nav collapses to a hamburger menu on mobile with a smooth slide-in animation
    - The mobile sheet lists nav items vertically with touch-friendly tap targets (min 44px height)
    - The sheet closes when a nav item is tapped or when the user taps outside
    - The nav feels lightweight — no heavy shadows or borders that compete with page content
  story_8:
    - All member pages are fully responsive: mobile (320px+), tablet (768px+), desktop (1024px+)
    - Status cards on the dashboard stack vertically on mobile, display in a 2-column grid on tablet, and a 3-column grid on desktop
    - Forms use single-column layout on mobile; two-column on desktop where appropriate (e.g., first name / last name side-by-side)
    - The auth shell's split-pane collapses to single-column on mobile with the brand panel as a slim header
  story_9:
    - Loading states use a subtle spinner or skeleton UI (not a blank screen)
    - Error messages are inline, contextual, and written in plain language (not technical jargon)
    - Network errors (gateway down, timeout) surface a friendly "Something went wrong" message with a retry CTA
    - Empty states across all surfaces (no payments, no activity, no entries) feel warm and actionable, not barren
  story_10:
    - All member pages share a consistent typographic scale (heading sizes, body text, labels)
    - Button styles (primary, secondary, danger) are visually consistent across all surfaces
    - Color usage (accent, success, warning, danger) is semantically consistent (green always means success, etc.)
    - Spacing rhythm (padding, margins, gaps) follows a consistent scale (e.g., 4px, 8px, 16px, 24px, 32px)

**edge_cases:**
  - Long names or emails (80+ char names, 60+ char emails) must not break layout; text truncates gracefully with ellipsis and full value accessible via hover/focus
  - Member with no surfaces enabled: dashboard empty state feels welcoming, not broken
  - Member with 50+ surface entries: index table with pagination remains performant and scannable
  - RTL (right-to-left) locales: out of scope — LTR only
  - Slow connections (3G): loading states appear within 200ms; no FOUC (flash of unstyled content)
  - Screen reader walkthrough: keyboard-only navigation works; all interactive elements have accessible labels; error messages are announced
  - Very short viewport (mobile landscape, iPhone SE): sticky top nav does not obscure content
  - Concurrent updates (optimistic locking): error message surfaces inline and clearly
  - Browser compatibility: modern evergreen browsers only (Chrome, Safari, Firefox, Edge — last 2 versions); no IE11

**out_of_scope:**
  - Admin pages (`/:cid/admin/*`) retain current design; no changes
  - Business logic changes: no controller, model, route, contract, activity, or mailer changes
  - New member features: no new pages, sections, or capabilities
  - Dark mode: light mode only; no theme switching
  - Internationalization: English-language UI only; no RTL support
  - New external dependencies: no new gems, npm packages, icon libraries, or fonts beyond Inter
  - Email templates: mailer views are out of scope
  - Performance optimization beyond asset hygiene: no code splitting, lazy loading, or service workers
  - Backend authorization or scoping changes: all role checks and `customer_id` scoping remain unchanged
  - Cross-customer access or platform-owner surfaces: member-facing pages only

**open_questions:**
  - (None — all necessary context is provided; UX designer has freedom within constraints to define visual language)

**ready_for_brainstorm:** true

**notes:** This is a pure presentation-layer refactor with no behavioral or backend changes. The 14 member ViewComponents, two layouts, and all member/auth view templates are in scope. The UX designer will define the visual language (color, typography, spacing, motion) within the hard constraints of TailwindCSS-only, StimulusJS-only, ViewComponent encapsulation, WCAG AA accessibility, and a 50KB asset budget. All existing Turbo/Stimulus behavior must remain intact.

---

**READY FOR UX.**
