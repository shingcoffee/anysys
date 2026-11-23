---
title: "Internationalization"
summary: "English and Simplified Chinese, chosen per request by SetLocale, with area-prefixed locale files and Stimulus values for JavaScript copy."
---

## Summary

The app has two locales: `:en` (the default) and `:"zh-CN"`. `SetLocale` wraps every request in `I18n.with_locale`. `LocalesController` stores a switch on the cookie and, when someone is signed in, on `Authentication::User#locale`. User-facing copy goes through `I18n`. Both locale files are required for every new string. JavaScript reads strings from Stimulus values whose English `default` matches the English translation, while the server passes the active locale on the mount element.

Missing `zh-CN` keys fall back to English because `config.i18n.fallbacks` is true. Developer reference and customer operational guides follow the same pair of locales, with separate Markdown roots and translation scopes; see [overview](overview) and [customer documentation](customer-documentation).

## Flow

```text
request
        |
        v
SetLocale#resolved_locale   (around_action, first hit wins)
        |
        1. params[:locale]          if it is an available locale
        2. current_user.locale
        3. cookies[:locale]
        4. Current.customer.locale  (tenant default; skipped when unset)
        5. Accept-Language          compatible_language_from(available_locales)
        6. I18n.default_locale      (:en)
        |
        v
I18n.with_locale
        |
        v
t(...) / I18n.t(...) from config/locales/<area>.en.yml
                       and config/locales/<area>.zh-CN.yml

PATCH /locale
        |
        v
LocalesController#update
  cookies[:locale] for one year
  current_user.update_column(:locale) when signed in
  same-origin referer: replace an existing locale query with the supported choice
  absent, malformed, or off-origin referer: root
```

## Implementation

`config/application.rb` sets `config.i18n.available_locales = [:en, :"zh-CN"]`, `config.i18n.default_locale = :en`, `config.i18n.fallbacks = true`, and appends `config/locales/**/*.{rb,yml}` to the load path. `SetLocale#available` accepts a value only when the symbol is in `I18n.available_locales`. Anything else is ignored, including `?locale=xx`. `from_customer` reads `Current.customer&.locale`, which is the optional column on `Customer` (blank becomes nil). The tenant value sits under the personal signals and above `Accept-Language`. Outside a tenant, `Current.customer` is nil and that step is skipped.

`LocalesController#update` is public: no tenant and no auth. It writes `cookies[:locale]` with `same_site: :lax` and a one-year expiry, and `update_column(:locale)` on the signed-in user. The route is `PATCH /locale`. It redirects to the same-origin referer, replacing an existing `locale` query parameter with the validated choice so stale request parameters cannot override the saved preference. Locale-free referers stay unchanged. An unknown locale skips both writes and leaves a safe referer unchanged, including its explicit locale.

`locale_redirect_location` uses `URI` for URL parsing and `Rack::Utils.parse_query` / `build_query` for query handling. Root-relative paths are accepted; absolute HTTP(S) URLs must match the request's scheme, host, and port and contain no user information. An absent, malformed, or off-origin referer falls back to `root_path`, including for unsupported locale requests. Tenant and article paths, search, other query keys and values (including repeated values and nested keys), and fragments are retained when rewriting the locale. `redirect_to` also sets `allow_other_host: false`.

Copy lives in area-prefixed pairs under `config/locales/`. Each area has `<area>.en.yml` and `<area>.zh-CN.yml`, and the top-level key is the area (`maint_platform`, `member`, `help`, `common`, `auth`, `customers`, and the `comp_*`, `settings_*`, `website_*`, `code_generator_*` files). Controllers and views call `t`. Models, activities, and other non-controller Ruby call `I18n.t` at call time. A constant may hold the key. It must not hold the result of `t` or `I18n.t`, because that freezes the locale that was current at load. The English string is the source text. `zh-CN` is a Simplified Chinese sentence with full-width punctuation, not a word-for-word gloss. Interpolation variables match on both sides.

`config/locales/en.yml` and `config/locales/app.zh-CN.yml` are the pair that is not named `<area>.en.yml` / `<area>.zh-CN.yml`. They hold `member.security.mfa` and `authentication.mfa_recovery`. `layout_catalog.en.yml` is the page-layout picker catalog (`layout_catalog.templates`, `layout_catalog.categories`, `layout_catalog.groups`). `validation_copy.en.yml` adds `maint_core.pages.configuration_errors` and `maint_core.flowcharts.structure_errors` / `server_validation`; Rails merges those keys into `maint_core`.

Stimulus controllers declare user-facing strings as values with an English `default`. The mount element passes the translated string as `data-<controller>-<name>-value`. `GrantsEditorController` is the pattern: `savingLabel` defaults to `"Saving..."`, and `grants_editor_component.html.erb` sets `data-grants-editor-saving-label-value` from `t("comp_admin.grants_editor.saving")`. ICU-style templates such as `"{count} change"` are replaced in JavaScript with `.replace()`. Specs under `spec/javascript` can construct the controller without data attributes and still see the English default.

Documentation article titles, summaries, and body copy live in paired Markdown files: developer reference under `doc/reference/{en,zh-CN}` and customer guides under `doc/customer/{en,zh-CN}`. `CustomerDocs::Catalog` contains 13 operational guide slugs and task-oriented required headings, separate from the developer catalog's implementation headings. Keep each catalog's files and sections in parity across locales; front matter supplies localized navigation titles and page headers.

`DeveloperDocs::Repository` receives `translation_scope:` along with the catalog, content root, and route helper. Its default `"developer_docs"` uses `config/locales/developer_docs.en.yml` and `developer_docs.zh-CN.yml`; `CustomerDocs::Repository` passes `"customer_docs"`, backed by `customer_docs.en.yml` and `customer_docs.zh-CN.yml`. Callout and anchor labels are translated with the repository's selected locale explicitly, even when a missing localized Markdown file falls back to English. Cache keys include the selected locale and translation scope to keep those labels separate.

`DeveloperDocs::ReaderComponent#reader_text` translates at render time using `translation_scope: "developer_docs"` by default. The customer view passes `"customer_docs"` for contents, search, groups, home/section navigation, previous/next links, and accessibility labels. The same lookup provides translated open/close labels to the `developer-docs-nav` Stimulus values. Homepage cards also read `home.*` and `group_descriptions.*` from that scope. The Help menu's Documentation label and customer-guide subtitle remain under the paired `chrome.help_menu.docs` keys.

An explicit request locale does not persist a preference; only `LocalesController#update` writes it. Customer guide navigation therefore preserves the effective language explicitly: the controller passes `route_options: { locale: current_locale }` to the repository, breadcrumbs and recovery links use `current_locale`, and the Help entry uses `I18n.locale`. Search and clear URLs include only the locale query; `ReaderComponent` receives `locale: current_locale` and adds hidden fields to both GET forms because browsers replace the action query on submission. Repository cache keys include route options to isolate localized article links. The repository's default `route_options: {}` and reader's default `locale: nil` keep developer links and search forms free of added locale parameters.

Both documentation readers use `DeveloperDocs::Highlighter` for inline and fenced code. Kramdown's gem-level syntax-highlighter registry survives Rails development reloads, so `Highlighter.install!` registers the current `Formatter` on every Markdown render. Retained formatter callbacks resolve `DeveloperDocs::Highlighter.highlight` and `DeveloperDocs::Highlighter::PRE_CLASS` explicitly, avoiding references through an unloaded lexical parent. The reload regression in `spec/services/developer_docs/highlighter_spec.rb` renders code across two real Rails reloads and exercises callbacks retained from before each reload.

### Flowchart action keys

Flowchart step-action copy lives in `config/locales/flowchart_actions_<area>.{en,zh-CN}.yml` (one pair per area, for example `flowchart_actions_communication`, `flowchart_actions_sms_document`, `flowchart_actions_outcome_payments`), with shared field labels and codes in `flowchart_actions_shared`, category and empty-option labels in `flowchart_actions_catalog`, and generic runtime messages in `flowchart_runtime.{en,zh-CN}.yml`. Each action has `flowchart_actions.<action>.{label, description, fields.<field>.{label, help, placeholder, options}, errors.<code>}` and `flowchart_runtime.errors.<action>.<code>` for the codes its emitted code passes to `Step.fail`. `ActionCatalog.export(locale:)` resolves them at call time, and `Step.fail` translates runtime codes in the request locale. The layout and lookup order are on [Code generators](code-generators).

The test environment sets `config.i18n.raise_on_missing_translations = true` (`config/environments/test.rb`), so a view, component or `t` call that hits a missing key fails its spec. `spec/services/code_generators/action_i18n_keys_spec.rb` checks every catalog action: label, description, field labels and option labels, `validate` codes and runtime codes must exist in both locales with `I18n.exists?(key, locale, fallback: false)`, runtime codes must be literal or explicitly expanded so the spec can enumerate them, and `%{}` variables must match between `en` and `zh-CN`.

## Where to pay attention

:::attention
`SetLocale#resolved_locale` stops at the first supported value. A signed-in user's `Authentication::User#locale` wins over `Customer#locale` and over `Accept-Language`. `LocalesController` writes both the cookie and the user column and replaces a stale explicit locale on the return URL. The redirected request therefore uses the selected language at step 1 when a locale query exists, or step 2 before the cookie when it does not.
:::

:::attention
`SetLocale#available` drops any locale outside `I18n.available_locales`. Adding a third language means changing `config/application.rb`, adding both files, and teaching `LocalesController` nothing extra: it already checks `I18n.available_locales`. A key added in `en` without the same key and the same interpolation variables in `zh-CN` falls back to English at runtime and is still an incomplete change.
:::

:::attention
`GrantsEditorController` keeps English in `static values` defaults and reads `this.savingLabelValue` (and the other label values). The translated string arrives only from the `data-grants-editor-*-value` attributes that `Admin::Settings::Modules::Authentication::GrantsEditorComponent` renders with `t`. A literal in the controller body is a hard-coded string the locale switch cannot change.
:::

:::attention
`Customer` normalizes blank `locale` to nil and validates inclusion in `I18n.available_locales`. That column is the tenant default inside `SetLocale#from_customer`. It does not override `params[:locale]`, `current_user.locale`, or `cookies[:locale]`.
:::

:::attention
Markdown source fallback does not satisfy locale parity. Publish every customer guide in both locales with `Before you start`, `Steps`, `What to expect`, `Troubleshooting`, and `Related guides`, or their `CustomerDocs::Catalog::REQUIRED_HEADINGS` Chinese equivalents. Do not translate strings in Ruby constants or hard-code reader labels; select the correct translation scope at render time.
:::

## Key code

```ruby
# config/application.rb
config.i18n.available_locales = [:en, :"zh-CN"]
config.i18n.default_locale    = :en
config.i18n.fallbacks         = true
config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.{rb,yml}")]
```

```ruby
# app/controllers/concerns/set_locale.rb
def resolved_locale
  from_params ||
    from_current_user ||
    from_cookie ||
    from_customer ||
    from_header ||
    I18n.default_locale
end
```

```ruby
# app/controllers/locales_controller.rb
def update
  locale = requested_locale

  if locale
    cookies[:locale] = { value: locale.to_s, expires: 1.year, same_site: :lax }
    current_user&.update_column(:locale, locale.to_s) if user_signed_in?
  end

  redirect_to locale_redirect_location(locale), allow_other_host: false
end
```

```javascript
// app/javascript/controllers/grants_editor_controller.js
    dirtyCountSingularFormat: { type: String, default: "{count} change" },
    dirtyCountPluralFormat: { type: String, default: "{count} changes" },
    grantedCounterFormat: { type: String, default: "{granted} / {total} granted" },
    discardConfirmFormat: { type: String, default: "Discard {count} change(s)?" },
    savingLabel: { type: String, default: "Saving..." },
    saveGrantsLabel: { type: String, default: "Save grants" },
```
