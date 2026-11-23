# Website module implementation plan

> For agentic workers: implement by lane (backend / security / frontend). Do **not** git commit. Do **not** switch models. Follow `docs/2026-09-20-website-module-design.md` and `docs/2026-09-20-website-module-ux.md`. I18n chrome already lives in `config/locales/website.{en,zh-CN}.yml` plus patches to feature_modules, admin_modules, admin_settings, maint_platform — reuse those keys, do not hard-code strings.

**Goal:** Ship Feature Module `website` so a tenant admin can enable it, compose static marketing pages from a cloned section kit, and publish them at `/:cid/site`.

**Architecture:** Separate from form `Page`. One `Website` per customer, many `WebsitePage` rows with JSON `sections`. Code-defined skeletons + section kit. Public layout is marketing, not `public_page`.

**Tech stack:** Rails 8.1 / SQLite / ViewComponent / Tailwind / Stimulus / Reform PORO activities / RSpec / Vitest.

## Global constraints

- Grok 4.6 Extra High only (already the session model).
- Roles: owner / admin / member only. No member builder.
- Admin URLs under `/:cid/admin/`. Public `/:cid/site`. No `/:cid/member/` website routes.
- Every customer table has `customer_id` (integer, indexed). `TenantScoped`.
- Tailwind + Stimulus + ViewComponent. No custom CSS/JS frameworks.
- I18n en + zh-CN for chrome. English values already in locale files.
- Beauty bar: public site must not look like the form card layout.
- No entity, flowchart, or `<form>` on public pages (locale switcher POST in nav is the exception).
- SQLite: partial unique index `where: "home = 1"`.
- Do not commit.

## File map

### Backend
- `db/migrate/YYYYMMDDHHMMSS_create_websites.rb`
- `app/models/website.rb`, `app/models/website_page.rb`
- `app/services/feature_modules/website/registration.rb`
- `app/services/feature_modules/website/provisioner.rb`
- `app/services/websites/theme.rb`
- `app/services/websites/section_kit.rb`
- `app/services/websites/href.rb`
- `app/services/websites/skeletons.rb` + `skeletons/presence.rb` etc.
- `app/services/websites/activities/{provision,save_site,save_page,destroy_page,reorder_pages,replace_skeleton}.rb`
- `app/services/websites/contracts/{site,page,section}.rb`
- `spec/factories/websites.rb`
- specs under `spec/models/`, `spec/services/websites/`

### Security
- `config/routes.rb` public site + admin modules/website + settings + platform skeletons
- Controllers listed in Task T-routes
- `Admin::Maintenance::Platform::ModuleSettings::NavComponent` MODULE_SECTIONS + path (this file is a component but is the only place platform tabs are registered — security lane owns this edit)
- `spec/routing/websites_routing_spec.rb`
- `spec/requests/websites/` auth + public 404/200

### Frontend
- `layouts/website.html.erb`
- `app/components/websites/**`
- Stimulus `website_nav_controller.js`, `website_builder_controller.js` + Vitest
- Icon in `ModuleSettingsHelper`
- Thin views that only render components if security did not add them

---

### T-model (backend)

**Produces:** `Website`, `WebsitePage`, registries, activities, contracts, provisioner, registration, factories, model/activity/contract specs.

Migration:

```ruby
create_table :websites do |t|
  t.integer :customer_id, null: false
  t.string :name, null: false
  t.string :tagline
  t.boolean :published, null: false, default: false
  t.string :skeleton_key, null: false, default: "presence"
  t.json :theme, null: false, default: {}
  t.json :seo, null: false, default: {}
  t.json :footer, null: false, default: {}
  t.timestamps
end
add_index :websites, :customer_id, unique: true

create_table :website_pages do |t|
  t.integer :customer_id, null: false
  t.integer :website_id, null: false
  t.string :title, null: false
  t.string :slug, null: false, default: ""
  t.integer :position, null: false, default: 0
  t.boolean :published, null: false, default: false
  t.boolean :home, null: false, default: false
  t.boolean :nav_visible, null: false, default: true
  t.json :sections, null: false, default: []
  t.timestamps
end
add_index :website_pages, :customer_id
add_index :website_pages, :website_id
add_index :website_pages, [:website_id, :slug], unique: true
add_index :website_pages, :website_id, unique: true, where: "home = 1", name: "index_website_pages_one_home"
```

`Website::DEFAULT_THEME = { "appearance" => "light", "accent" => "azure", "type" => "sans", "density" => "spacious" }` — do not I18n this constant.

Skeletons: four keys with English starter copy in Ruby (DB-stored, not chrome). Beautiful marketing English, not lorem.

Section types exactly as design table. `Websites::SectionKit::TYPES`. Unknown type skipped at render, rejected on save.

Hrefs: `Websites::Href` — allow `\A[a-z0-9]+(?:-[a-z0-9]+)*\z` or `\Ahttps://`. Reject `javascript:`, `http://`.

Registration: key `website`, name `Website`, description `Customer introduction and marketing website — static pages, no forms`, inactive, not required, configuration_schema default_skeleton_key presence. sidebar entries pages + settings site. entries_for("pages") tenant-scoped WebsitePage. provision! / deprovision! via provisioner.

Deprovision: `website.update!(published: false)` if present.

Replace skeleton: destroy pages, recreate unpublished pages from skeleton, keep site.published as-is, set skeleton_key.

Run: `bundle exec rspec spec/models/website_spec.rb spec/models/website_page_spec.rb spec/services/websites spec/services/feature_modules/website`

---

### T-routes (security)

Public (inside `/:customer_id` public section, near `page/:uuid`):

```
get "site", to: "websites/pages#home", as: :website_home
get "site/:page_slug", to: "websites/pages#show", as: :website_page, constraints: { page_slug: /[a-z0-9]+(?:-[a-z0-9]+)*/ }
```

Admin modules:

```
namespace :website, module: "modules/website" do
  get "/", to: "pages#index", as: :root
  resources :pages, except: [:show] do
    member { get :preview }
    collection { patch :reorder }
  end
  resource :publication, only: :update
end
```

Settings:

```
namespace :website, module: "settings/modules/website" do
  get "/", to: "sites#show"
  resource :site, only: %i[show update]
  resource :skeleton, only: :create
end
```

Platform:

```
namespace :website, module: "maintenance/platform/website" do
  get "skeletons", to: "skeletons#show"
end
```

inside existing `scope :module_settings`.

Controllers:
- `Websites::PagesController` (public) — no auth. 404 unless module enabled AND site.published AND page.published. Home uses `home: true`. Layout `website`.
- `Admin::Modules::Website::BaseController` — `dashboard_menu_item :modules`, `require_website_module!` → 404.
- Pages CRUD + preview + reorder. Preview uses layout `website`, ignores published, still requires module + tenant record.
- Publication PATCH sets site.published.
- Settings SitesController dashboard_menu_item :settings.
- Platform SkeletonsController — platform namespace inherits owner gate.

Record loads: `Website.for_current_customer` / `WebsitePage.for_current_customer`. Public uses `params[:customer_id]` after TenantContext.

NavComponent: `"website" => %i[skeletons]`, path_for `:skeletons` → website skeletons helper, CURRENT_ID_ALIASES skeletons: :skeletons.

Auth specs: admin-guarded GET for admin paths; public unpublished 404; member forbidden on admin; other tenant 404; module disabled 404.

Do not implement section ViewComponents (frontend). Thin views may render components by the names in the UX doc.

---

### T-component-public (frontend)

Beauty-critical. Follow UX § P/Q exactly (theme tokens, type scale, ASCII). Files under `app/components/websites/`. Layout `app/views/layouts/website.html.erb`. Stimulus `website_nav` + Vitest 100%.

No `<form>` in section components. Escape rich_text. Placeholder gradient, never empty img.

---

### T-component-modules (frontend)

Composer + kit picker + section editors + icon in ModuleSettingsHelper. Stimulus `website_builder` + Vitest 100%. Index can stay a thin view using AdminTableComponent.

---

### T-component-settings (frontend)

Settings form + skeleton replace + platform SkeletonsGalleryComponent.

---

### T-qa

After lanes merge: request specs isolation, system happy path, no public forms, Vitest coverage for the two controllers.
