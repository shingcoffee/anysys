# Admin page render link — implementation plan

**Date:** 2026-10-21 · **Status:** Ready for implementation

**UX contract:** [Admin page render link](../specs/2026-10-21-admin-page-render-link-ux.md).

Deliver a localized **Open in admin** item immediately after Preview in both responsive row menus, gated by `launched? && visible_to?(:admin)`, opening the existing admin render endpoint in a new tab with full dashboard chrome and the visited tenant preserved.

## 1. Frontend lane — anysys-frontend-developer

Files:

- `app/components/admin/pages/ops_table_component.rb`
- `app/components/admin/pages/ops_table_component.html.erb`
- `config/locales/admin_misc.en.yml`
- `config/locales/admin_misc.zh-CN.yml`
- `doc/reference/en/page-rendering.md`
- `doc/reference/zh-CN/page-rendering.md`

Tasks:

1. Add a small route accessor (e.g. `admin_render_path(page)`) delegating to `helpers.admin_maintenance_page_render_path(customer_id, page)`. Use the component's visited-customer prop for shared and owned rows.
2. Add the item after Preview in **both** mobile and desktop menus when `page_row.launched? && page_row.visible_to?(:admin)`. Copy Preview's item classes and attributes: `target: "_blank"`, `rel: "noopener noreferrer"`, `data: { turbo_frame: "_top" }`. Reuse `menu-placement` and its current markup.
3. Add `admin_misc.pages.open_in_admin`: en **`Open in admin`**, zh-CN **`在后台打开`**. Keep Preview's `maint_core.pages.preview` and draft availability. Use runtime `t(...)`; keep locale keys in parity.
4. Add a matching paragraph near the existing `PageRendersController#show` description in both reference pages. Suggested text:

   **en:** From `/:cid/admin/pages` (including entity-filtered and uncategorized lists), the row menu offers **Open in admin** only when `launched? && visible_to?(:admin)`. It opens `/:cid/admin/maintenance/pages/:id/render` in a new tab with the full dashboard layout, using `target="_blank"`, `rel="noopener noreferrer"`, and `data-turbo-frame="_top"`. Both owned and shared pages retain the visited customer prefix; shared pages resolve that customer's effective definition. **Preview** remains available for drafts.

   **zh-CN:** 在 `/:cid/admin/pages`（含按实体筛选及未分类列表）中，仅当 `launched? && visible_to?(:admin)` 时，行菜单才显示**在后台打开**。该操作使用 `target="_blank"`、`rel="noopener noreferrer"` 和 `data-turbo-frame="_top"`，在新标签页打开 `/:cid/admin/maintenance/pages/:id/render`，展示完整后台布局。自有页面和共享页面均保留当前所访客户前缀；共享页面按该客户的生效定义渲染。草稿仍可通过**预览**打开。

## 2. QA lane — anysys-qa-engineer

Extend `spec/components/admin/pages/ops_table_component_spec.rb`:

- Assert the new href, localized label, menu ordering, `_blank`, `noopener noreferrer`, and `_top` **within each responsive branch**, inspecting closed-menu links with `visible: :all` as appropriate.
- Cover launched pages at `admin`, `member`, and `public` visibility. The existing live fixture is member-visible; it must receive the action.
- Cover omission for a draft and for a launched row whose `visible_to?(:admin)` is false (stub the predicate or use a stubbed invalid-visibility row). Draft Preview retains its href and attributes.
- Cover shared and owned rows with an explicit component customer ID; shared rows have no row customer ID. Verify both en and zh-CN wording.

Extend `spec/requests/admin/pages_spec.rb` for the integrated list → render journey:

- Sign in as a same-tenant admin, GET the list, locate the new action for a real launched owned page, then GET its extracted href **without a Turbo-Frame header**. Assert 200, the page content/name, and dashboard navigation markup.
- Repeat with a real launched shared page. Assert that the href retains the current customer's prefix and rendering succeeds in that context. Use an existing shared-page fixture pattern; a tenant override fixture can demonstrate the effective definition where useful.
- Verify draft omission plus retained Preview, Chinese action wording, and exclusion of another tenant's page from the list. Add a representative entity-filtered/uncategorized assertion if needed to verify the shared component wiring.
- Reuse the existing authentication helpers and fixtures. Extend the existing request file rather than adding a redundant integration harness.

## 3. Release lane — anysys-release-engineer

Run the targeted regressions after implementation:

```bash
bundle exec rspec spec/components/admin/pages/ops_table_component_spec.rb spec/requests/admin/pages_spec.rb spec/requests/admin/maintenance/page_renders_spec.rb
```

The existing render suite covers admin-route authorization, unpublished-page rejection, foreign-tenant denial, and platform-owner access. Record real results; distinguish environmental blockers or pre-existing failures from this change.

Smoke-test at 375px, 768px, and 1280px in en/zh-CN: eligible item after Preview, bottom-row popup placement, keyboard/touch activation, draft Preview, and a new tab with complete dashboard navigation under the original customer prefix. Rebuild Tailwind assets if required by the changed template. Follow AGENTS.md asset-cleanup and `SKIP_AUTH=1` instructions if restarting a development server; use authenticated specs for authorization verification.

## 4. Review lane — anysys-code-reviewer / anysys-tech-lead

Review correctness and conventions: both responsive branches, exact predicate rather than scalar visibility equality, current-tenant route generation for shared pages, link security/frame attributes, retained draft Preview, runtime I18n with matching locale keys, and matched reference paragraphs. Confirm the implementation uses the existing ViewComponent/Tailwind/Stimulus pattern and destination authorization.

The workspace already contains extensive user edits, especially locale and reference files. Inspect current diffs before editing, apply only the scoped hunks above, and preserve all unrelated work. Completion requires the scoped implementation/docs, passing targeted verification with evidence, and review of the final diff.
