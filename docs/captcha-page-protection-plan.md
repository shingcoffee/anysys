# Captcha page protection — implementation plan

> Execute via SDLC lanes. Do **not** git commit.

**Goal:** Per-form captcha toggles on platform module-settings (heuristic public forms) and per-page toggles on Settings → Captcha.

**Docs:** `docs/captcha-page-protection-design.md`, `docs/captcha-page-protection-ux.md`

## File ownership (no overlap)

**Backend:** `db/migrate/*surface_settings*`, `app/models/captcha/surface_settings.rb`, `app/services/captcha/surface_catalog.rb`, `app/services/captcha/activities/toggle_*.rb`, `app/services/captcha/contracts/*`, matching specs under `spec/models` and `spec/services`.

**Security:** `config/routes.rb`, controllers + `captcha_protectable.rb`, request/routing/protectable specs.

**Frontend:** ViewComponents, ERB, locales, `WidgetComponent` `surface:`, `ModuleToggleComponent` optional `aria_label:`, component specs. No models/routes/controllers.

## APIs (lock)

```
Captcha::SurfaceCatalog.surfaces
  # => array of OpenStruct/hash: key, group, path, default_enabled?, fail_closed?, name_i18n_key
Captcha::SurfaceCatalog.find(key) # nil if unknown
Captcha::SurfaceSettings.instance
Captcha::SurfaceSettings.enabled?(key)  # missing key → catalog default
Captcha::Activities::TogglePlatformSurface.call(surface_key:, enabled:)
Captcha::Activities::TogglePage.call(page:, enabled:)
```

Routes:

```
PATCH /:cid/admin/maintenance/platform/module_settings/captcha/surfaces
  extra_params surface_key + enabled 1/0
  helper: admin_maintenance_platform_module_settings_captcha_surfaces_path(cid)

GET  /:cid/admin/settings/modules/captcha → Captcha::StatusController#show
PATCH /:cid/admin/settings/modules/captcha/pages/:id
  helper: admin_settings_modules_captcha_page_path(cid, page)
```

Do not commit.
