# Specification: Email Template Workspace Refactor v2

## 1. Introduction & Objectives
The email template workspace is currently compact and crowded. To improve user comfort and ease of use, we are refactoring both the template creation (`new`) and edit (`edit`) workflows:
1. **Creation page (`new`):** Re-imagined as a highly focused, spacious, single-column writing experience. All complex and technical configurations (Key, Category, Message stream, Variables) are completely omitted.
2. **Default status on Creation:** The template status defaults to `draft`. We will display a clean "Activate template immediately" checkbox (defaulting to unchecked) so the template is only activated if explicitly checked.
3. **Editing page (`edit`):** Implements a beautiful three-tab layout using the Stimulus `section-tabs` controller to keep settings and versions accessible but organized.
   - **Tab 1: ✍️ Composer & Preview:** Split editor view with auto-sync and dry-run test-send.
   - **Tab 2: ⚙️ Settings:** Advanced/technical configuration fields (Key - read-only, Stream, Category, Variables, Status).
   - **Tab 3: 📋 Version History:** Embeds the template version list (snapshot, view, and restore actions) directly in the workspace.

---

## 2. Page & Layout Architecture

### A. Template Creation (`new` page)
The template creation view at `/:cid/admin/modules/emails/templates/new` will render a spacious, single-column layout containing only:
- **Header:** Title & Subtitle.
- **Name Field:** Full-width.
- **Subject Field:** Full-width.
- **Compose Canvas:** Standard toggleable Editor (Rich Text / Code Editor) & Plain Text Fallback.
- **Activate Immediately Toggle:** A checkbox to set status to `active` immediately; defaults to unchecked.
- **Submit Actions:** Cancel & Create Template.

### B. Template Editing (`edit` page)
The template editing view at `/:cid/admin/modules/emails/templates/:id/edit` will use a tabbed structure using Stimulus `section-tabs`:
- **Header:** breadcrumbs, Name, Versions and Delete buttons.
- **Tabs Nav:**
  - **✍️ Composer & Preview**
  - **⚙️ Settings**
  - **📋 Version History**
- **Panels:**
  - **Composer & Preview Panel:** The side-by-side interactive split editor.
  - **Settings Panel:** Technical configurations in a clean grid.
  - **Version History Panel:** Lists saved snapshots, authors, and dates, with View and Restore buttons.

---

## 3. UI/UX Specifications (Tailwind Classes)
- **Tabs Nav:** Container `-mb-px flex gap-6` with active/inactive state class swapping on `a` elements:
  - Active: `border-accent text-accent border-b-2 px-1 py-3 text-sm font-semibold`
  - Inactive: `border-transparent text-text-muted hover:text-text border-b-2 px-1 py-3 text-sm font-medium`
- **Activate immediately checkbox:** Standard Tailwind inline flex:
  - `class="h-4 w-4 rounded border-gray-300 text-primary focus:ring-primary cursor-pointer"`

---

## 4. Internationalization (I18n)
All labels, button text, tooltips, and feedback messages will be defined in both:
- `config/locales/admin_modules.en.yml`
- `config/locales/admin_modules.zh-CN.yml`

New keys will be added under `admin_modules.emails.templates.form`:
- `activate_immediately`: "Activate immediately / 立即启用"
- `tab_composer`: "Composer & Preview / 编辑与预览"
- `tab_settings`: "Settings / 模板设置"
- `tab_versions`: "Version History / 版本历史"

---

## 5. Verification & Testing Plan
1. **RSpec Request Specs:** Verify that submitting the template creation form with `activate_immediately` unchecked creates a `draft` template, and checked creates an `active` template.
2. **Vitest Unit Tests:** Ensure all modified Stimulus controllers (such as `remote_template_preview_controller.test.js`) continue to pass and maintain 100% line/branch coverage.
