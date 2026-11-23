# Themed Templates Visual Redesign — Design Spec

**Date:** 2026-06-11
**Scope:** Pure visual redesign of themed templates for member and public audiences.
No schema, route, controller, or editor UI changes. Tailwind + Stimulus only.

---

## 1. Design Direction Summary

### What changes and why

The current rendering is generic: `gray-300` borders, flat white cards, basic
focus rings, a hardcoded `bg-gray-50 / bg-white card` public chrome that ignores
the page theme entirely. The goal is to make each of the six presets feel like a
distinct, polished form product — Typeform / Tally / Notion-forms quality — while
keeping the system backward-compatible (existing stored theme keys continue to
render sensibly).

Three interconnected improvements:

1. **Theme-aware public chrome** — `app/views/layouts/public_page.html.erb` and
   `app/views/public_pages/show.html.erb` are currently static. They must read
   the page theme and apply a matching page background, header treatment, and card
   style.

2. **Richer ThemeResolver maps** — every `COLOR_PALETTES` entry gains new keys
   (`gradient_from`, `gradient_to`, `soft_bg`, `soft_hover`, `ring_color`,
   `ring_offset_color`). `INPUT_STYLES`, `LABEL_STYLE_MAP`, `BUTTON_STYLE_MAP`,
   `FORM_BG_MAP` all get upgraded to use literal full-class strings instead of
   string surgery, allowing the safelist to shrink.

3. **Component-level polish** — inputs gain `hover:` shadow, `focus:` ring-offset,
   and `transition-shadow` polish; divider label mask uses the form background
   color; callout/quote/section get accent-derived styling; file upload gets a
   theme-aware hover state; wizard gets themed step badges and animated connector;
   rating stars use amber (justified below).

### Rating star color decision: amber

Stars are universally expected to be amber/gold by users (Yelp, Amazon, Google
all use amber). Accent-derived stars (e.g. indigo stars) read as selected state
rather than a rating scale. **Pick: `text-amber-400 fill-current` for filled
stars, `text-gray-300` for empty.** This is consistent across all presets — the
accent color is used for the focus ring on the star button, not for the fill.

---

## 2. Per-Preset Personality Table

| Preset | Page bg treatment | Card style | Typography | Input character | Button character | Distinctive flourish |
|--------|------------------|------------|------------|-----------------|-----------------|----------------------|
| **modern** | Soft indigo-tinted radial gradient: `bg-gradient-to-br from-slate-50 to-indigo-50` | White, `rounded-xl`, `shadow-lg`, border `border-indigo-100` | Inter, default weight | Outline, `rounded-lg`, focus ring indigo with `ring-offset-2` | Gradient `from-indigo-600 to-indigo-500`, shadow lift on hover | Subtle heading accent bar (left border `border-l-2 border-indigo-300` on sections) |
| **minimalist** | Pure white: `bg-white` | No card shell — content floats directly on the page background; `shadow-none`, `border-none` | Inter, airy tracking; labels all-caps | Underline only, hairline `border-b border-gray-200`, focus deepens to `border-gray-700` | Ghost/outline: `border border-gray-400 text-gray-700 hover:bg-gray-50`, `rounded-sm` | 24px vertical rhythm, extra letter-spacing on labels, no card chrome |
| **bold** | Rose tinted: `bg-rose-50` | White with thick accent-top border: `border-t-4 border-rose-500 rounded-2xl shadow-md` | Inter, bold labels | Filled `bg-rose-50 rounded-full`, `focus:ring-rose-500 ring-offset-2` | Filled solid `bg-rose-600 hover:bg-rose-700 rounded-full`, scale on active `active:scale-95` | Large chunky `text-4xl` page title in rose, pill-shaped input corners |
| **elegant** | Warm paper toned: `bg-amber-50/40` (maps to new `warm` bg entry) | Ivory card `bg-amber-50/60 rounded-lg shadow-sm border border-amber-200/60` | Serif (`font-serif`), refined label tracking | Outline `border-amber-200 focus:border-violet-400 focus:ring-violet-300 rounded-md` | Soft: `bg-violet-100 text-violet-800 hover:bg-violet-200`, no shadow | Serif heading, warm paper tones throughout, relaxed `space-y-8` field rhythm |
| **playful** | Light emerald wash: `bg-emerald-50/50` | White, `rounded-3xl`, colorful `shadow-emerald-100 shadow-lg`, `border-none` | Inter, friendly tracking | Filled `bg-emerald-50 rounded-2xl`, bouncy `hover:bg-emerald-100 transition-all duration-150` | Gradient `from-emerald-500 to-teal-400 rounded-full` with `hover:shadow-emerald-200 hover:shadow-md active:scale-95` | Rounded-everything aesthetic, springy hover states, colorful badges |
| **showcase** | Rich dramatic gradient: `bg-gradient-to-br from-violet-950 via-violet-900 to-indigo-900` | White on dark, `rounded-2xl shadow-2xl`, crisp | Inter, modern SaaS, white header text on gradient hero | Outline `bg-white/95 rounded-lg focus:ring-violet-400 ring-offset-2` | Gradient `from-violet-500 to-indigo-500 rounded-lg shadow-lg hover:shadow-violet-300/50 active:scale-95` | Dark gradient hero header, white card floats over dark bg, dramatic contrast |

---

## 3. Exact New/Changed ThemeResolver Map Contents

Below are the complete literal Ruby hash snippets implementing the redesign.
The frontend developer replaces the corresponding constants in
`app/components/concerns/theme_resolver.rb`.

### 3.1 COLOR_PALETTES (enriched with new keys)

New keys added to every palette entry:
- `gradient_from` — `from-<hue>-600` literal for gradient button bg start
- `gradient_to` — `to-<hue>-500` literal for gradient button bg end
- `soft_bg` — `bg-<hue>-50` for soft button background (was computed via `.sub`)
- `soft_hover` — `hover:bg-<hue>-100` for soft button hover (was computed via `.sub`)
- `outline_hover` — `hover:bg-<hue>-50` for outline button hover
- `ring_color` — `ring-<hue>-500` for focus rings (distinct from the old `ring` key which was `focus:ring-<hue>-500`)
- `ring_offset_color` — `focus:ring-offset-white` (constant; included for completeness; themed surfaces may override via page chrome)
- `border_accent` — `border-<hue>-200` for themed card top-border treatment (bold preset)
- `border_accent_strong` — `border-<hue>-500` for bold card accent strip

```ruby
COLOR_PALETTES = {
  "indigo" => {
    bg: "bg-indigo-600",
    hover: "hover:bg-indigo-700",
    ring: "focus:ring-indigo-500",
    border: "focus:border-indigo-500",
    text: "text-indigo-600",
    light_bg: "bg-indigo-50",
    # new keys
    gradient_from: "from-indigo-600",
    gradient_to: "to-indigo-500",
    soft_bg: "bg-indigo-50",
    soft_hover: "hover:bg-indigo-100",
    outline_hover: "hover:bg-indigo-50",
    ring_color: "ring-indigo-500",
    ring_offset_color: "focus:ring-offset-white",
    border_accent: "border-indigo-200",
    border_accent_strong: "border-indigo-500"
  },
  "blue" => {
    bg: "bg-blue-600",
    hover: "hover:bg-blue-700",
    ring: "focus:ring-blue-500",
    border: "focus:border-blue-500",
    text: "text-blue-600",
    light_bg: "bg-blue-50",
    gradient_from: "from-blue-600",
    gradient_to: "to-blue-500",
    soft_bg: "bg-blue-50",
    soft_hover: "hover:bg-blue-100",
    outline_hover: "hover:bg-blue-50",
    ring_color: "ring-blue-500",
    ring_offset_color: "focus:ring-offset-white",
    border_accent: "border-blue-200",
    border_accent_strong: "border-blue-500"
  },
  "emerald" => {
    bg: "bg-emerald-600",
    hover: "hover:bg-emerald-700",
    ring: "focus:ring-emerald-500",
    border: "focus:border-emerald-500",
    text: "text-emerald-600",
    light_bg: "bg-emerald-50",
    gradient_from: "from-emerald-500",
    gradient_to: "to-teal-400",
    soft_bg: "bg-emerald-50",
    soft_hover: "hover:bg-emerald-100",
    outline_hover: "hover:bg-emerald-50",
    ring_color: "ring-emerald-500",
    ring_offset_color: "focus:ring-offset-white",
    border_accent: "border-emerald-200",
    border_accent_strong: "border-emerald-500"
  },
  "rose" => {
    bg: "bg-rose-600",
    hover: "hover:bg-rose-700",
    ring: "focus:ring-rose-500",
    border: "focus:border-rose-500",
    text: "text-rose-600",
    light_bg: "bg-rose-50",
    gradient_from: "from-rose-600",
    gradient_to: "to-rose-500",
    soft_bg: "bg-rose-50",
    soft_hover: "hover:bg-rose-100",
    outline_hover: "hover:bg-rose-50",
    ring_color: "ring-rose-500",
    ring_offset_color: "focus:ring-offset-white",
    border_accent: "border-rose-200",
    border_accent_strong: "border-rose-500"
  },
  "amber" => {
    bg: "bg-amber-600",
    hover: "hover:bg-amber-700",
    ring: "focus:ring-amber-500",
    border: "focus:border-amber-500",
    text: "text-amber-600",
    light_bg: "bg-amber-50",
    gradient_from: "from-amber-600",
    gradient_to: "to-amber-500",
    soft_bg: "bg-amber-50",
    soft_hover: "hover:bg-amber-100",
    outline_hover: "hover:bg-amber-50",
    ring_color: "ring-amber-500",
    ring_offset_color: "focus:ring-offset-white",
    border_accent: "border-amber-200",
    border_accent_strong: "border-amber-500"
  },
  "violet" => {
    bg: "bg-violet-600",
    hover: "hover:bg-violet-700",
    ring: "focus:ring-violet-500",
    border: "focus:border-violet-500",
    text: "text-violet-600",
    light_bg: "bg-violet-50",
    gradient_from: "from-violet-500",
    gradient_to: "to-indigo-500",
    soft_bg: "bg-violet-100",
    soft_hover: "hover:bg-violet-200",
    outline_hover: "hover:bg-violet-50",
    ring_color: "ring-violet-500",
    ring_offset_color: "focus:ring-offset-white",
    border_accent: "border-violet-200",
    border_accent_strong: "border-violet-500"
  },
  "teal" => {
    bg: "bg-teal-600",
    hover: "hover:bg-teal-700",
    ring: "focus:ring-teal-500",
    border: "focus:border-teal-500",
    text: "text-teal-600",
    light_bg: "bg-teal-50",
    gradient_from: "from-teal-600",
    gradient_to: "to-teal-500",
    soft_bg: "bg-teal-50",
    soft_hover: "hover:bg-teal-100",
    outline_hover: "hover:bg-teal-50",
    ring_color: "ring-teal-500",
    ring_offset_color: "focus:ring-offset-white",
    border_accent: "border-teal-200",
    border_accent_strong: "border-teal-500"
  },
  "slate" => {
    bg: "bg-slate-700",
    hover: "hover:bg-slate-800",
    ring: "focus:ring-slate-500",
    border: "focus:border-slate-500",
    text: "text-slate-700",
    light_bg: "bg-slate-50",
    gradient_from: "from-slate-700",
    gradient_to: "to-slate-600",
    soft_bg: "bg-slate-100",
    soft_hover: "hover:bg-slate-200",
    outline_hover: "hover:bg-slate-50",
    ring_color: "ring-slate-500",
    ring_offset_color: "focus:ring-offset-white",
    border_accent: "border-slate-200",
    border_accent_strong: "border-slate-500"
  }
}.freeze
```

### 3.2 INPUT_STYLES (enriched)

The existing three keys keep working. Each value is enriched with hover and
transition classes — they are literal strings now, no surgery needed.

```ruby
INPUT_STYLES = {
  "outline"   => "border border-gray-300 bg-white hover:border-gray-400 hover:shadow-sm transition-all duration-150",
  "filled"    => "border-0 bg-gray-100 hover:bg-gray-200/70 transition-colors duration-150",
  "underline" => "border-0 border-b-2 border-gray-300 bg-transparent rounded-none hover:border-gray-500 transition-colors duration-150"
}.freeze
```

### 3.3 LABEL_STYLE_MAP (enriched)

```ruby
LABEL_STYLE_MAP = {
  "default"   => "block text-sm font-medium text-gray-700 mb-1 transition-colors",
  "bold"      => "block text-sm font-bold text-gray-900 mb-1",
  "uppercase" => "block text-xs font-semibold text-gray-500 uppercase tracking-widest mb-2",
  "floating"  => "block text-xs font-medium text-gray-500 mb-0.5"
}.freeze
```

### 3.4 BUTTON_STYLE_MAP (literal lambdas, no string surgery)

Replace the current lambda-with-sub approach with literal key lookups.
This is the critical Tailwind v4 change — `from-*` and `to-*` classes
now come directly from `gradient_from`/`gradient_to` keys, which are
literal strings in the COLOR_PALETTES hash above.

```ruby
BUTTON_STYLE_MAP = {
  "filled" => ->(palette) {
    "#{palette[:bg]} #{palette[:hover]} text-white " \
    "shadow-sm hover:shadow-md active:scale-95 transition-all duration-150"
  },
  "outline" => ->(palette) {
    "border-2 #{palette[:border_accent_strong]} #{palette[:text]} bg-transparent " \
    "#{palette[:outline_hover]} active:scale-95 transition-all duration-150"
  },
  "soft" => ->(palette) {
    "#{palette[:soft_bg]} #{palette[:text]} #{palette[:soft_hover]} " \
    "active:scale-95 transition-all duration-150"
  },
  "gradient" => ->(palette) {
    "bg-gradient-to-r #{palette[:gradient_from]} #{palette[:gradient_to]} text-white " \
    "shadow-sm hover:shadow-md hover:opacity-95 active:scale-95 transition-all duration-150"
  }
}.freeze
```

Note: `border_accent_strong` is the new literal key (e.g. `border-indigo-500`).
The `border` key on palette is still `focus:border-indigo-500` which is used for
input focus borders — not appropriate as a button border. The new key separates
concerns cleanly.

### 3.5 FORM_BG_MAP (enriched: warm gets a warmer card tone, new keys for showcase)

```ruby
FORM_BG_MAP = {
  "white" => "bg-white",
  "gray"  => "bg-gray-50",
  "warm"  => "bg-amber-50/60"
}.freeze
```

The `warm` value changes from `bg-amber-50/30` to `bg-amber-50/60` for the
elegant preset to give the ivory card a more distinct warm tone.

### 3.6 PAGE_CHROME_BG_MAP (new constant — page-level background per preset)

This new map is keyed by `primary_color` + a new theme key `page_bg` (default:
`"auto"`). For the six presets, `page_bg` is set in THEME_PRESETS. For
custom/legacy pages without `page_bg`, `"auto"` falls back to `"bg-gray-50"`.

The key `page_bg` stores one of the string keys below, NOT a Tailwind class.
This keeps the class strings literal and scannable.

```ruby
PAGE_CHROME_BG_MAP = {
  "modern"    => "bg-gradient-to-br from-slate-50 to-indigo-50",
  "minimalist"=> "bg-white",
  "bold"      => "bg-rose-50",
  "elegant"   => "bg-amber-50",
  "playful"   => "bg-emerald-50",
  "showcase"  => "bg-gradient-to-br from-violet-950 via-violet-900 to-indigo-900",
  "default"   => "bg-gray-50"
}.freeze
```

Resolver helper to add to ThemeResolver (private section):

```ruby
def resolve_page_chrome_bg(theme)
  preset = resolve_theme(theme)["preset"]
  PAGE_CHROME_BG_MAP[preset] || PAGE_CHROME_BG_MAP["default"]
end
```

The `preset` key is written by the page builder when the user picks a preset.
Existing pages without `preset` fall back to `"default"` which is `bg-gray-50`
— same as the current hardcoded value, so no visual regression.

### 3.7 PAGE_CHROME_HEADER_MAP (new constant — header text color per preset)

```ruby
PAGE_CHROME_HEADER_MAP = {
  "modern"    => "text-gray-900",
  "minimalist"=> "text-gray-900",
  "bold"      => "text-rose-700",
  "elegant"   => "text-violet-900",
  "playful"   => "text-emerald-800",
  "showcase"  => "text-white",
  "default"   => "text-gray-900"
}.freeze
```

Resolver helper:

```ruby
def resolve_page_chrome_header_color(theme)
  preset = resolve_theme(theme)["preset"]
  PAGE_CHROME_HEADER_MAP[preset] || PAGE_CHROME_HEADER_MAP["default"]
end
```

### 3.8 PAGE_CHROME_DESC_MAP (new constant — description text color per preset)

```ruby
PAGE_CHROME_DESC_MAP = {
  "modern"    => "text-gray-500",
  "minimalist"=> "text-gray-400",
  "bold"      => "text-rose-400",
  "elegant"   => "text-violet-400",
  "playful"   => "text-emerald-600",
  "showcase"  => "text-violet-200",
  "default"   => "text-gray-500"
}.freeze
```

Resolver helper:

```ruby
def resolve_page_chrome_desc_color(theme)
  preset = resolve_theme(theme)["preset"]
  PAGE_CHROME_DESC_MAP[preset] || PAGE_CHROME_DESC_MAP["default"]
end
```

### 3.9 PAGE_CHROME_CARD_MAP (new constant — card wrapper classes per preset)

The card wrapper is the white box that contains the `FormFields::PageComponent`
inside the public chrome. `PageComponent` already applies `form_shadow`,
`form_border`, `form_bg`, and `form_radius` from the theme — so the chrome card
wrapper must NOT duplicate those. Instead it provides the outer presentational
shell.

```ruby
PAGE_CHROME_CARD_MAP = {
  "modern"    => "rounded-xl overflow-hidden",
  "minimalist"=> "",
  "bold"      => "rounded-2xl overflow-hidden border-t-4 border-rose-500",
  "elegant"   => "rounded-lg overflow-hidden",
  "playful"   => "rounded-3xl overflow-hidden",
  "showcase"  => "rounded-2xl overflow-hidden shadow-2xl",
  "default"   => "rounded-xl overflow-hidden"
}.freeze
```

Resolver helper:

```ruby
def resolve_page_chrome_card(theme)
  preset = resolve_theme(theme)["preset"]
  PAGE_CHROME_CARD_MAP[preset] || PAGE_CHROME_CARD_MAP["default"]
end
```

### 3.10 FORM_BORDER_MAP (enriched for better contrast)

```ruby
FORM_BORDER_MAP = {
  "none"    => "",
  "subtle"  => "border border-gray-100",
  "visible" => "border border-gray-200",
  "strong"  => "border-2 border-gray-300"
}.freeze
```

(Unchanged from current — the map values are already literal strings. No change
needed here. Bold preset accent-top-border is handled by PAGE_CHROME_CARD_MAP so
it doesn't bloat FORM_BORDER_MAP.)

### 3.11 THEME_PRESETS (updated with new `preset` key + page_bg key removed in
favour of PAGE_CHROME maps, plus preset-personality adjustments)

The key change is adding `"preset"` to each entry so `resolve_page_chrome_*`
resolvers can dispatch correctly. Additionally a few slot values are updated for
better personality.

```ruby
THEME_PRESETS = {
  "modern" => {
    "preset" => "modern",
    "primary_color" => "indigo", "accent_color" => "indigo", "font_family" => "sans",
    "border_radius" => "lg", "input_style" => "outline", "form_background" => "white",
    "form_width" => "xl", "form_shadow" => "lg", "form_padding" => "spacious",
    "form_border" => "none", "field_spacing" => "normal", "input_size" => "md",
    "label_style" => "default", "button_style" => "gradient", "button_width" => "full", "button_size" => "md"
  },
  "minimalist" => {
    "preset" => "minimalist",
    "primary_color" => "slate", "accent_color" => "slate", "font_family" => "sans",
    "border_radius" => "sm", "input_style" => "underline", "form_background" => "white",
    "form_width" => "lg", "form_shadow" => "none", "form_padding" => "normal",
    "form_border" => "none", "field_spacing" => "tight", "input_size" => "md",
    "label_style" => "uppercase", "button_style" => "outline", "button_width" => "auto", "button_size" => "md"
  },
  "bold" => {
    "preset" => "bold",
    "primary_color" => "rose", "accent_color" => "rose", "font_family" => "sans",
    "border_radius" => "full", "input_style" => "filled", "form_background" => "white",
    "form_width" => "xl", "form_shadow" => "md", "form_padding" => "normal",
    "form_border" => "none", "field_spacing" => "normal", "input_size" => "lg",
    "label_style" => "bold", "button_style" => "filled", "button_width" => "full", "button_size" => "lg"
  },
  "elegant" => {
    "preset" => "elegant",
    "primary_color" => "violet", "accent_color" => "violet", "font_family" => "serif",
    "border_radius" => "md", "input_style" => "outline", "form_background" => "warm",
    "form_width" => "lg", "form_shadow" => "sm", "form_padding" => "spacious",
    "form_border" => "subtle", "field_spacing" => "relaxed", "input_size" => "md",
    "label_style" => "default", "button_style" => "soft", "button_width" => "full", "button_size" => "md"
  },
  "playful" => {
    "preset" => "playful",
    "primary_color" => "emerald", "accent_color" => "emerald", "font_family" => "sans",
    "border_radius" => "full", "input_style" => "filled", "form_background" => "white",
    "form_width" => "xl", "form_shadow" => "lg", "form_padding" => "spacious",
    "form_border" => "none", "field_spacing" => "normal", "input_size" => "lg",
    "label_style" => "default", "button_style" => "gradient", "button_width" => "full", "button_size" => "lg"
  },
  "showcase" => {
    "preset" => "showcase",
    "primary_color" => "violet", "accent_color" => "violet", "font_family" => "sans",
    "border_radius" => "lg", "input_style" => "outline", "form_background" => "white",
    "form_width" => "full", "form_shadow" => "xl", "form_padding" => "generous",
    "form_border" => "subtle", "field_spacing" => "relaxed", "input_size" => "lg",
    "label_style" => "uppercase", "button_style" => "gradient", "button_width" => "full", "button_size" => "lg"
  }
}.freeze
```

Backward compatibility: existing pages that have `theme` JSON without a `preset`
key will receive `nil` from `resolve_theme(theme)["preset"]`, which falls
through to `"default"` in all `PAGE_CHROME_*` resolvers — same as the current
hardcoded gray background.

---

## 4. Per-Component Spec: Exact Class Treatment

### 4.1 Chrome — Public Layout (`app/views/layouts/public_page.html.erb`)

**Before:**
```html
<body class="bg-gray-50 min-h-screen flex flex-col">
  <main class="flex-1 flex items-start justify-center py-12 px-4">
    <div class="w-full max-w-2xl">
      <!-- flash -->
      <div class="bg-white rounded-xl shadow-sm border border-gray-200">
        <div class="px-6 py-5 border-b border-gray-100">
          <h1 class="text-xl font-semibold text-gray-900">...</h1>
        </div>
        <div class="px-6 py-6">...content...</div>
      </div>
    </div>
  </main>
</body>
```

**After (new structure):**

The layout must receive the page theme. The layout already has `@page` in scope
(it sets `<title><%= @page.name %>`), so the theme is accessible as
`@page.configuration_json&.dig("theme") || {}`.

```html
<body class="<%= resolve_page_chrome_bg(@page.configuration_json&.dig('theme') || {}) %> min-h-screen flex flex-col">
  <main class="flex-1 flex items-start justify-center py-10 sm:py-16 px-4">
    <div class="w-full max-w-2xl">

      <%# Flash notice — always visible regardless of background %>
      <% if notice.present? %>
        <div class="mb-6 flex items-center gap-3 px-4 py-3 bg-white/90 backdrop-blur-sm border border-green-200 rounded-xl shadow-sm text-sm text-green-800">
          <svg class="w-4 h-4 flex-shrink-0 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <%= notice %>
        </div>
      <% end %>

      <%# Page title/description header — outside card, themed color %>
      <div class="mb-6 px-1">
        <h1 class="text-2xl sm:text-3xl font-bold tracking-tight <%= resolve_page_chrome_header_color(@page.configuration_json&.dig('theme') || {}) %>">
          <%= @page.name %>
        </h1>
        <% if @page.description.present? %>
          <p class="mt-2 text-sm sm:text-base <%= resolve_page_chrome_desc_color(@page.configuration_json&.dig('theme') || {}) %>">
            <%= @page.description %>
          </p>
        <% end %>
      </div>

      <%# Card shell — chromatic per preset %>
      <div class="<%= resolve_page_chrome_card(@page.configuration_json&.dig('theme') || {}) %>">
        <%= yield %>
      </div>

    </div>
  </main>
</body>
```

Key changes:
- Body `bg-*` is now theme-driven via `resolve_page_chrome_bg`.
- Flash notice uses `bg-white/90 backdrop-blur-sm` so it's legible on any
  background including showcase's dark gradient.
- Title/description moved OUTSIDE the card, with themed text color via
  `resolve_page_chrome_header_color` / `resolve_page_chrome_desc_color`.
- Card wrapper uses `resolve_page_chrome_card` for preset-specific shell.
- `ThemeResolver` must be included in the layout's helper or called via a
  helper method. The cleanest approach: a `PublicPagesHelper` that includes
  `ThemeResolver` and exposes the four resolver helpers as public methods.

**The layout must include `ThemeResolver` helpers.** Since layouts do not
directly include concerns, the recommended approach is to add a `public_pages`
application helper that delegates to ThemeResolver — or to call these resolvers
from the controller and expose them as instance variables (`@page_chrome_bg`,
`@page_chrome_header_color`, `@page_chrome_desc_color`, `@page_chrome_card`)
set before rendering. Either approach keeps ERB clean.

### 4.2 Chrome — Public Page Show (`app/views/public_pages/show.html.erb`)

**Before:**
```erb
<% if @content.present? %>
  <%= render inline: @content %>
<% else %>
  <p class="text-sm text-gray-400 text-center py-8">This form has no content yet.</p>
<% end %>
```

**After:** No structural change needed — `FormFields::PageComponent` already
wraps the content with theme-derived classes. The `show.html.erb` remains the
same. The title/description header has been moved to the layout.

The empty state text gains a slight tweak to work on themed backgrounds:
```erb
<p class="text-sm text-gray-400 text-center py-12">This form has no content yet.</p>
```

### 4.3 Chrome — Member Show (`app/views/member/pages/show.html.erb`)

Member view is inside the member shell. The card chrome here is handled by the
shell's `.card` design token, not the page theme chrome. Do NOT apply
PAGE_CHROME_BG to the member shell. The member page show just needs to pass the
theme to the `render inline:` content, which it does via `@content` (the
generated ERB already passes `theme:` to components).

Minor visual improvement: the `border-b border-border-subtle` header separator
gets a margin-bottom that matches the field spacing of the resolved theme. Since
we cannot access the theme in the show.html.erb without more work, leave as-is —
the existing `.card` treatment is sufficient for the member shell. No change
required.

### 4.4 Chrome — Admin Page Render (`app/views/admin/maintenance/page_renders/show.html.erb`)

Admin preview. The card already uses `.card` design tokens and the breadcrumb.
No chrome change required — the admin preview shows "how the form looks" inside
a neutral admin card, which is appropriate.

### 4.5 Container — `FormFields::PageComponent`

`page_component.html.erb` currently shows a basic `text-2xl font-bold text-gray-900`
title. Since the title is now shown in the public chrome header (outside the
card) for public pages, the `show_title` prop will typically be `false` for
public audience. However, for the **member** and **admin** audience, `show_title`
may be `true`, so the title treatment inside the card is still needed.

**page_component.html.erb — title treatment upgrade:**
```erb
<%# Title inside card (member/admin audience, or when show_title: true) %>
<% if show_title && title.present? %>
  <h1 class="text-2xl font-bold text-gray-900 mb-2 tracking-tight leading-tight"><%= title %></h1>
<% end %>
<% if show_description && description.present? %>
  <p class="text-sm text-gray-500 mb-6 leading-relaxed"><%= description %></p>
<% end %>
```

No other changes to `page_component.rb` or its `wrapper_classes` method —
those already compose the theme-derived classes correctly.

### 4.6 Container — `FormFields::FormComponent`

`form_component.html.erb` — add `focus-within` subtle ring to the form container
for the minimalist preset (where there is no card border). Since `focus-within`
can't be conditioned without a Stimulus controller or a wrapper div, the cleanest
approach is a thin wrapping `div` with a class driven by `form_container_classes`:

Add to `form_component.rb`:
```ruby
def form_container_classes
  # Provides a subtle focus-within highlight for borderless themes
  "group"
end
```

`form_component.html.erb` changes:
```erb
<div class="<%= form_container_classes %>">
  <form action="..." ...>
    ...
    <button type="submit" class="<%= submit_button_classes %>">
```

The submit button classes already include `transition-all duration-200` — just
the enriched `BUTTON_STYLE_MAP` lambdas (Section 3.4 above) provide the
improved shadow/scale micro-interactions.

### 4.7 Container — `FormFields::WizardComponent`

**wizard_component.html.erb changes:**

**Step badges** — currently plain colored circles managed by JS. Enhance the
base template classes so the JS has better default states:

Current badge base class (inline in the template):
```
flex-shrink-0 flex items-center justify-center w-8 h-8 rounded-full text-sm font-semibold transition-all duration-200
```

After (same, no change needed to ERB — the Stimulus controller `wizard` already
manages active/completed/future states by adding/removing inline styles or
data-driven classes. The VISUAL upgrade is in how the Stimulus controller applies
colors — see Stimulus notes in Section 5).

**Progress connector** — currently `flex-1 h-px mx-3`. Upgrade:
```
flex-1 h-0.5 mx-3 rounded-full transition-colors duration-300
```
(0.5 = 2px height vs 1px, rounded caps, same JS control target)

**Navigation footer** — currently `border-t border-gray-200`. Upgrade:
```
flex items-center justify-between mt-8 pt-6 border-t border-gray-100
```

**Secondary button** in `wizard_component.rb`:
```ruby
def secondary_button_classes
  radius = resolve_radius_class(theme)
  size   = resolve_button_size(theme)
  "#{NAV_BUTTON_WIDTH} #{size} #{radius} bg-white text-gray-600 border border-gray-200 " \
    "hover:bg-gray-50 hover:border-gray-300 transition-all duration-150 focus:ring-2 " \
    "focus:ring-gray-200 focus:ring-offset-2 font-medium"
end
```

### 4.8 Inputs — `BaseFieldComponent` (affects all text/textarea/number/date/email/etc.)

`resolve_input_classes` in `ThemeResolver` currently emits:
```
w-full <size> <input_base> <radius> focus:ring-2 <ring> <border> transition-colors
```

After (add `focus:ring-offset-2`, `focus:shadow-sm`, better transition):
```ruby
def resolve_input_classes(theme)
  resolved = resolve_theme(theme)
  palette = color_palette(theme)
  input_base = INPUT_STYLES[resolved["input_style"]] || INPUT_STYLES["outline"]
  radius = resolved["input_style"] == "underline" ? "" : resolve_radius_class(theme)
  size = INPUT_SIZE_MAP[resolved["input_size"]] || INPUT_SIZE_MAP["md"]

  "w-full #{size} #{input_base} #{radius} focus:outline-none focus:ring-2 focus:ring-offset-2 #{palette[:ring_color]} #{palette[:border]} focus:shadow-sm transition-all duration-150".squish
end
```

Note: `palette[:ring_color]` is the new literal key `ring-indigo-500` (without
the `focus:` prefix), while `focus:ring-2 focus:ring-offset-2` is hardcoded. The
old `palette[:ring]` was `focus:ring-indigo-500` which doubled the `focus:` — the
new approach separates the modifier from the value cleanly.

### 4.9 Inputs — `SelectFieldComponent`

The `select` element gets the same `resolve_input_classes` upgrade. Additionally,
native `<select>` has an appearance chevron that clashes with some themes. Add
`appearance-none bg-no-repeat bg-right pr-8` pattern — but since this requires
a background-image SVG inline, it's out of scope for this spec (it would need a
tiny Tailwind plugin or inline style). Leave `<select>` with the enhanced focus
treatment from `resolve_input_classes` and accept the native chevron.

### 4.10 Inputs — `RadioFieldComponent`

**radio_field_component.html.erb** — radio input gets accent color and improved
hover container:

**Before:**
```html
<input type="radio" ... class="w-4 h-4 text-indigo-600 border-gray-300 focus:ring-indigo-500">
<span class="ml-2 text-sm text-gray-700 group-hover:text-gray-900">...</span>
```

**After:** Pass theme-derived accent color. Since `RadioFieldComponent` already
extends `BaseFieldComponent` which includes `ThemeResolver`, it has access to
`color_palette(theme)`.

In `radio_field_component.rb` add a helper:
```ruby
def radio_input_classes
  palette = color_palette(theme)
  "w-4 h-4 #{palette[:text]} border-gray-300 #{palette[:ring]} focus:ring-2 " \
  "transition-colors cursor-pointer"
end

def radio_option_wrapper_classes
  "flex items-center gap-2 cursor-pointer group py-0.5 px-1 rounded " \
  "hover:bg-gray-50 transition-colors duration-100"
end
```

`radio_field_component.html.erb` — update:
```erb
<label class="<%= radio_option_wrapper_classes %> group">
  <input type="radio" ... class="<%= radio_input_classes %>">
  <span class="text-sm text-gray-700 group-hover:text-gray-900 transition-colors"><%= option['label'] %></span>
</label>
```

### 4.11 Inputs — `CheckboxFieldComponent`

`checkbox_field_component.html.erb` currently renders via `render_input` in
`BaseFieldComponent`. The `input_classes` from `resolve_input_classes` are
correct for text-type inputs but wrong for checkboxes (checkbox doesn't need
`w-full` or size padding).

In `CheckboxFieldComponent` (which extends `BaseFieldComponent`), override
`input_classes`:
```ruby
def input_classes
  palette = color_palette(theme)
  "w-4 h-4 #{palette[:text]} border-gray-300 #{palette[:ring]} focus:ring-2 rounded transition-colors cursor-pointer"
end
```

### 4.12 Inputs — `ToggleFieldComponent`

`toggle_field_component.html.erb` — the toggle track and thumb currently
hardcode `peer-focus:ring-indigo-500` and `peer-checked:bg-indigo-600`.

**After (theme-driven):** `ToggleFieldComponent` already extends
`BaseFieldComponent` which includes `ThemeResolver`. Add a helper method:
```ruby
def toggle_track_classes
  palette = color_palette(theme)
  "w-11 h-6 bg-gray-200 rounded-full peer " \
  "peer-focus:ring-2 #{palette[:ring_color]} peer-focus:ring-offset-2 " \
  "peer-checked:after:translate-x-full peer-checked:after:border-white " \
  "after:content-[''] after:absolute after:top-0.5 after:left-[2px] " \
  "after:bg-white after:border-gray-300 after:border after:rounded-full " \
  "after:h-5 after:w-5 after:transition-all #{palette[:bg]} " \
  "peer-checked:#{palette[:bg].sub('bg-', 'bg-')} transition-colors duration-150"
end
```

Wait — `peer-checked:bg-indigo-600` pattern requires a literal `peer-checked:`
modifier that JIT CANNOT derive from palette. This is a Tailwind v4 constraint.

**Resolution:** Since the checked color IS the primary color bg (e.g.
`peer-checked:bg-indigo-600`), and all 8 hue/600 combinations must be literal,
add them to the safelist OR expand `toggle_track_classes` to return the class
string where `peer-checked:bg-<hue>-600` is already a literal in the hash:

Add new key to `COLOR_PALETTES`: `checked_track` with value
`peer-checked:bg-indigo-600` (etc.) as a literal string per palette.

```ruby
# Additional key to add to each COLOR_PALETTES entry:
"indigo"  => { ..., checked_track: "peer-checked:bg-indigo-600" },
"blue"    => { ..., checked_track: "peer-checked:bg-blue-600" },
"emerald" => { ..., checked_track: "peer-checked:bg-emerald-600" },
"rose"    => { ..., checked_track: "peer-checked:bg-rose-600" },
"amber"   => { ..., checked_track: "peer-checked:bg-amber-600" },
"violet"  => { ..., checked_track: "peer-checked:bg-violet-600" },
"teal"    => { ..., checked_track: "peer-checked:bg-teal-600" },
"slate"   => { ..., checked_track: "peer-checked:bg-slate-700" }
```

Then `toggle_track_classes`:
```ruby
def toggle_track_classes
  palette = color_palette(theme)
  "w-11 h-6 bg-gray-200 rounded-full peer " \
  "peer-focus:ring-2 #{palette[:ring_color]} peer-focus:ring-offset-2 " \
  "peer-checked:after:translate-x-full peer-checked:after:border-white " \
  "after:content-[''] after:absolute after:top-0.5 after:left-[2px] " \
  "after:bg-white after:border-gray-300 after:border after:rounded-full " \
  "after:h-5 after:w-5 after:transition-all #{palette[:checked_track]} transition-colors duration-150"
end
```

`toggle_field_component.html.erb` replaces the hardcoded div class with
`<%= toggle_track_classes %>`.

### 4.13 Inputs — `RatingFieldComponent`

**rating_field_component.html.erb** — star fill color changes from
`text-yellow-400` to `text-amber-400` (same visual tone, more standard).
Focus ring on each star button becomes theme-derived.

**rating_field_component.html.erb after:**
```erb
<button type="button"
        ...
        class="p-1 transition-colors focus:outline-none focus:ring-2 <%= color_palette(theme)[:ring_color] %> rounded">
  <svg class="w-6 h-6 transition-colors duration-150 <%= star <= current_value ? 'text-amber-400 fill-current' : 'text-gray-300' %>"
       ...>
```

Add `theme` to `RatingFieldComponent` — it already inherits from
`BaseFieldComponent` so `theme` and `color_palette(theme)` are available.

The rating label text changes from `text-gray-500` to `text-gray-400` for a
lighter, more editorial feel:
```erb
<span class="ml-2 text-sm text-gray-400" data-rating-target="label">
```

### 4.14 Inputs — `FileUploadFieldComponent`

**file_upload_field_component.html.erb** — the dropzone currently hardcodes
`hover:border-indigo-400 hover:bg-indigo-50`. Make it theme-aware.

In `FileUploadFieldComponent` (which should include or be converted to extend
`BaseFieldComponent`; it currently does not extend it — verify), add:
```ruby
def dropzone_classes
  palette = color_palette(theme)
  # accent_palette for light bg
  accent = resolve_accent_palette(theme)
  "relative border-2 border-dashed border-gray-300 rounded-lg p-6 sm:p-8 text-center " \
  "hover:border-gray-400 hover:shadow-md " \
  "focus-within:border-gray-400 " \
  "transition-all duration-200 cursor-pointer group"
end

def dropzone_icon_classes
  "mx-auto h-12 w-12 text-gray-300 group-hover:text-gray-400 transition-colors duration-150"
end

def upload_cta_classes
  palette = color_palette(theme)
  "text-sm font-medium #{palette[:text]}"
end
```

The "Click to upload" text color comes from `palette[:text]` (e.g.
`text-indigo-600`). The hover border is neutral `hover:border-gray-400` rather
than accent-colored — this avoids the hardcoded `indigo` and keeps the dropzone
neutral until file-selected state (which is JS-controlled).

`file_upload_field_component.html.erb` after:
```erb
<div data-file-drop-zone class="<%= dropzone_classes %>">
  <input type="file" ... class="absolute inset-0 w-full h-full opacity-0 cursor-pointer">
  <svg class="<%= dropzone_icon_classes %>" stroke="currentColor" fill="none" viewBox="0 0 48 48">
    ...
  </svg>
  <div class="mt-4">
    <span class="<%= upload_cta_classes %>">Click to upload</span>
    <span class="text-sm text-gray-500"> or drag and drop</span>
  </div>
  <p class="mt-1 text-xs text-gray-400">...</p>
</div>
```

Note: `FileUploadFieldComponent` does not currently extend `BaseFieldComponent`.
It must be updated to include `ThemeResolver` (or extend `BaseFieldComponent`) to
get access to `color_palette(theme)`.

### 4.15 Layout — `DividerElementComponent` (the label mask bug fix)

**Current bug:** `<span class="px-2 bg-white text-gray-500">` — hardcoded
`bg-white` causes a white rectangle patch on warm/gray/themed form backgrounds.

**Fix:** `DividerElementComponent` must accept `theme:` and resolve the form bg.

`divider_element_component.rb` changes:
```ruby
def initialize(label: nil, spacing: 'md', theme: {})
  @label = label
  @spacing = spacing
  @theme = theme
end

def label_bg_class
  FORM_BG_MAP[resolve_theme(@theme)["form_background"]] || FORM_BG_MAP["white"]
end
```

Include `ThemeResolver` in `DividerElementComponent`.

`divider_element_component.html.erb` after:
```erb
<div class="<%= spacing_class %>">
  <% if label.present? %>
    <div class="relative">
      <div class="absolute inset-0 flex items-center">
        <div class="w-full border-t border-gray-200"></div>
      </div>
      <div class="relative flex justify-center text-sm">
        <span class="px-3 <%= label_bg_class %> text-gray-400 text-xs font-medium tracking-wide uppercase">
          <%= label %>
        </span>
      </div>
    </div>
  <% else %>
    <hr class="border-gray-200">
  <% end %>
</div>
```

Also: the divider line `border-gray-300` is softened to `border-gray-200` for
elegance; label text size changes from `text-sm` to `text-xs uppercase tracking-wide`.

`PageContentGenerator` must pass `theme:` to `DividerElementComponent` when
generating ERB for dividers.

### 4.16 Layout — `SectionElementComponent`

**section_element_component.html.erb** — the "linked" variant hardcodes
`border-l-2 border-indigo-300` and `text-indigo-700`. This should be
accent-derived. However, `SectionElementComponent` does not currently include
`ThemeResolver` and does not accept `theme:`.

Add `theme: {}` param and include `ThemeResolver`. Then:

**After (linked variant):**
```erb
<fieldset class="mb-6 pl-4 border-l-2 <%= color_palette(theme)[:border_accent_strong] %> border-opacity-60">
  <legend class="text-xs font-semibold tracking-widest uppercase <%= color_palette(theme)[:text] %>">
    <%= title %>
  </legend>
  <% if description.present? %>
    <p class="mt-1 text-sm text-gray-500"><%= description %></p>
  <% end %>
</fieldset>
```

**After (default variant):**
```erb
<fieldset class="mb-8">
  <legend class="text-lg font-semibold text-gray-900 pb-2 border-b border-gray-100 w-full"><%= title %></legend>
  <% if description.present? %>
    <p class="mt-1.5 text-sm text-gray-500"><%= description %></p>
  <% end %>
</fieldset>
```

Changes: removed the separate `<div class="mt-2 border-t border-gray-200"></div>`
separator (merged into legend `border-b`), slightly more whitespace (`mb-8` vs
`mb-6`), `tracking-widest` on linked variant.

`PageContentGenerator` must pass `theme:` to `SectionElementComponent`.

### 4.17 Layout — `CalloutElementComponent`

Currently hardcodes `border-l-4 border-indigo-400 bg-indigo-50`.
Must be accent-derived and accept `theme:`.

`callout_element_component.rb` changes:
```ruby
include ThemeResolver
def initialize(content_text:, theme: {})
  @content_text = content_text
  @theme = theme
end
```

`callout_element_component.html.erb` after:
```erb
<% accent = resolve_accent_palette(theme) %>
<div class="mb-4 pl-4 border-l-4 <%= accent[:border] %> <%= accent[:bg] %> py-3.5 pr-4 rounded-r-lg">
  <p class="text-sm <%= accent[:text] %> leading-relaxed font-medium"><%= content_text %></p>
</div>
```

Note: `ACCENT_PALETTES` entries already have `border`, `bg`, and `text` keys.
`resolve_accent_palette(theme)` is the existing ThemeResolver method. All classes
are literal strings in the existing `ACCENT_PALETTES` constant — no safelist
needed.

`PageContentGenerator` passes `theme:` to `CalloutElementComponent`.

### 4.18 Layout — `QuoteElementComponent`

Currently hardcodes `border-l-4 border-gray-300`. Give it a slightly more
editorial treatment.

No theme dependency — quote intentionally stays neutral to work on all presets.

`quote_element_component.html.erb` after:
```erb
<blockquote class="mb-4 pl-5 border-l-2 border-gray-300 py-2 pr-4">
  <p class="text-base text-gray-600 italic leading-relaxed"><%= content_text %></p>
  <% if attribution_present? %>
    <cite class="block mt-3 text-xs text-gray-400 not-italic tracking-wide uppercase">&mdash; <%= attribution %></cite>
  <% end %>
</blockquote>
```

Changes: `border-l-4` → `border-l-2` (thinner, more editorial); text `text-sm` →
`text-base` (more readable); attribution tracking `uppercase`.

### 4.19 Layout — `HeadingElementComponent`

`heading_element_component.rb` — the LEVELS map gets slightly richer type scale:

```ruby
LEVELS = {
  1 => "text-3xl font-bold tracking-tight",
  2 => "text-2xl font-bold tracking-tight",
  3 => "text-xl font-semibold",
  4 => "text-lg font-semibold",
  5 => "text-base font-semibold",
  6 => "text-sm font-semibold uppercase tracking-wide"
}.freeze
```

`heading_classes` method — color stays `text-gray-900` for all levels for
readability.

### 4.20 Layout — `CardElementComponent`

`card_element_component.html.erb` after:
```erb
<div class="mb-4 rounded-xl border border-gray-100 bg-white p-5 shadow-sm hover:shadow-md transition-shadow duration-200">
  <h4 class="text-sm font-semibold text-gray-900 leading-snug"><%= title %></h4>
  <% if content_present? %>
    <p class="mt-2 text-sm text-gray-500 leading-relaxed"><%= content_text %></p>
  <% end %>
</div>
```

Changes: `border-gray-200` → `border-gray-100`, added `shadow-sm hover:shadow-md
transition-shadow duration-200`, `rounded-lg` → `rounded-xl`.

### 4.21 Layout — `AlertElementComponent`

AlertElementComponent VARIANTS are already hardcoded semantic colors (info/warning/
success/danger) — these should NOT be theme-derived; they carry semantic meaning
that must be consistent. No change to color logic.

Visual polish: add `rounded-xl` (currently `rounded-lg`) and `shadow-sm` for lift.

`alert_element_component.html.erb` after:
```erb
<div class="mb-4 p-4 rounded-xl border shadow-sm <%= config[:bg] %> <%= config[:border] %>">
  <div class="flex items-start gap-3">
    <svg class="w-5 h-5 flex-shrink-0 mt-0.5 <%= config[:icon_color] %>" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <%= icon_svg.html_safe %>
    </svg>
    <p class="text-sm leading-relaxed <%= config[:text] %>"><%= content_text %></p>
  </div>
</div>
```

### 4.22 Layout — `ProgressBarElementComponent`

`progress_bar_element_component.html.erb` after:
```erb
<div class="mb-4">
  <% if label_present? %>
    <div class="flex items-center justify-between mb-2">
      <span class="text-sm font-medium text-gray-700"><%= label %></span>
      <span class="text-xs font-medium text-gray-400"><%= progress_value %>%</span>
    </div>
  <% end %>
  <div class="w-full bg-gray-100 rounded-full h-2 overflow-hidden">
    <div class="<%= color_class %> h-2 rounded-full transition-all duration-500 ease-out" style="width: <%= progress_value %>%"></div>
  </div>
</div>
```

Changes: track `bg-gray-200` → `bg-gray-100` (softer), bar height stays `h-2`
(was `h-2.5` → now `h-2`, slimmer editorial look), `overflow-hidden` on track
prevents bar from bleeding outside rounded corners, `transition-all duration-500
ease-out` for smooth JS-driven updates.

### 4.23 Layout — `ParagraphElementComponent`

`paragraph_element_component.html.erb` after:
```erb
<div class="mb-4">
  <p class="text-sm text-gray-600 leading-relaxed <%= alignment_class %>"><%= content_text %></p>
</div>
```

No change needed — already clean. Optionally upgrade to `text-gray-500` for a
lighter tone on white forms, but `text-gray-600` is safe.

### 4.24 Layout — `ButtonElementComponent`

`button_element_component.html.erb` after:
```erb
<div class="mb-4 <%= alignment_class %>">
  <a href="<%= button_url %>"
     class="inline-block font-medium <%= radius_class %> border transition-all duration-150 active:scale-95 <%= variant_classes %> <%= size_classes %>">
    <%= content_text %>
  </a>
</div>
```

Added `active:scale-95` for micro-interaction on click.

---

## 5. Responsive Behavior Notes

### Public layout (`public_page.html.erb`)

- Page title: `text-2xl sm:text-3xl` — scales from compact mobile to full
  desktop heading.
- Main padding: `py-10 sm:py-16 px-4` — tighter on mobile.
- Card wrapper `max-w-2xl` is replaced by the form's own `FORM_WIDTH_MAP` —
  do NOT double-constrain. Remove the hardcoded `max-w-2xl` wrapper from the
  layout; the `FormFields::PageComponent` already sets its own `max-w-*` via
  `resolve_form_width`.

  Revised layout outer wrapper: `w-full mx-auto px-4 sm:px-6`.

- Flash notice: full width on all breakpoints, `rounded-xl`.
- Showcase preset dark background: ensure the outer `<main>` is at least
  `min-h-screen` so the dark gradient fills the full viewport.

### Wizard step indicators

- Step labels: `hidden sm:block` already present — correct.
- Step badges: `w-8 h-8` on all breakpoints — fine.
- Nav toolbar: `flex-col gap-3 sm:flex-row` if step counter + buttons overflow
  on very narrow screens. Current layout (`flex items-center justify-between`) is
  fine on 375px+ since buttons are `w-auto px-6`.

### Half/third width fields collapsing

`PageContentGenerator` already emits `col-span-6` (half) / `col-span-4` (third)
in a 12-column grid, with a `sm:grid-cols-12` breakpoint. These classes are
literal in the generator — no change needed. Confirm the grid container uses
`grid grid-cols-1 sm:grid-cols-12 gap-x-4 gap-y-0`.

### Minimalist preset (no card shell)

On mobile, the minimalist preset renders content directly on white. Ensure
`px-4` padding on the outer wrapper prevents content from touching screen edges.

---

## 6. Safelist Changes in `app/assets/tailwind/application.css`

### Lines to REMOVE (string-surgery classes replaced by literal keys)

```css
/* REMOVE these four lines — they were needed for BUTTON_STYLE_MAP string surgery */
@source inline("from-{indigo,blue,emerald,rose,amber,violet,teal,slate}-600");
@source inline("to-{indigo,blue,emerald,rose,amber,violet,teal,slate}-500");
@source inline("hover:bg-{indigo,blue,emerald,rose,amber,violet,teal,slate}-100");
@source inline("hover:bg-{indigo,blue,emerald,rose,amber,violet,teal,slate}-600/10");
```

These are replaced by:
- `gradient_from` / `gradient_to` literal keys in COLOR_PALETTES (gradient button)
- `soft_hover` literal keys in COLOR_PALETTES (soft button)
- `outline_hover` literal keys in COLOR_PALETTES (outline button)

All these literals appear in `theme_resolver.rb` source, which Tailwind v4 scans.

### Lines to ADD (new literal classes that appear in new helpers or component ERBs
but NOT in .rb files that Tailwind scans by default)

The `PAGE_CHROME_*` maps contain Tailwind classes as values of Ruby hash literals.
Tailwind v4 scans `.rb` files, so these will be discovered automatically from
`theme_resolver.rb`. No new safelist entries needed for those.

Classes in `page_component.html.erb`, `wizard_component.html.erb`, ERB templates
— these are all scanned automatically.

The ONLY classes that need safelisting are those built by string interpolation at
runtime (the string-surgery pattern). After this redesign, there should be none
left except:

- `peer-checked:bg-{hue}-600` / `peer-checked:bg-{hue}-700` — these are now
  stored as `checked_track` literal keys in COLOR_PALETTES, so they ARE literal
  strings in `theme_resolver.rb` and will be scanned automatically. No safelist
  entry needed.

**Net result:** The 4 `@source inline(...)` lines in `application.css` can be
REMOVED entirely. No new `@source inline(...)` lines are needed.

However, retain the comment block explaining why the section exists (in case
future additions need it):
```css
/* Safelist: add @source inline(...) entries here if ThemeResolver ever builds
   class strings by string surgery again. Currently empty because all themed
   classes use full literal strings per palette entry. */
```

---

## 7. Out-of-Scope Reminders

- No page-builder editor UI changes (the palette picker, preset selector, etc.
  continue to work exactly as today — this spec only changes what the presets
  render as).
- No schema changes. `page.configuration_json["theme"]["preset"]` is read but
  never written by this spec — it is already written by the editor when a user
  picks a preset.
- No new Stimulus controllers. All micro-interactions are Tailwind utility classes
  (`hover:`, `active:`, `focus:`, `transition-*`). The existing `wizard` and
  `rating` controllers continue to apply their dynamic classes — the spec only
  changes the base template classes they start from.
- No member shell chrome changes. The `.card` design token on the member layout
  is intentionally unchanged.
- No admin shell chrome changes.

---

## 8. Accessibility Notes

### Contrast on showcase dark background

The showcase preset uses `bg-gradient-to-br from-violet-950 via-violet-900
to-indigo-900`. The title text `text-white` on `violet-950` achieves WCAG AAA
contrast (white on near-black). The description `text-violet-200` on
`violet-900` is approximately 7:1 — passes AAA. The white card on the dark
background provides the full contrast boundary.

### Focus visibility

The redesigned `resolve_input_classes` adds `focus:ring-offset-2` to all inputs.
This creates a 2px gap between the input border and the focus ring, making the
ring visible even on white backgrounds. The ring color is the palette's accent —
ensure all palette accent colors at 500 weight on white pass 3:1 (WCAG AA for
non-text UI elements). All current palette hues at 500 on white pass this
threshold.

### Rating star button focus

Each star button has `focus:ring-2 <palette[:ring_color]>`. The `rounded` class
on the button keeps the ring from being a square rectangle. Screen readers read
the star number via `data-value` — the component should ensure `aria-label` is
set on each button (this is a pre-existing gap, noted here, out of scope for this
spec to fix).

### Toggle contrast

The toggle track in unchecked state is `bg-gray-200` — the white thumb on
`gray-200` achieves approximately 1.7:1, which is below WCAG AA. This is a
pre-existing condition across all form builders; adding a `border border-gray-400`
around the thumb would help but is a separate accessibility task.

### Flash notice on dark backgrounds

The flash notice uses `bg-white/90 backdrop-blur-sm` which ensures it is always
legible regardless of the page background. The `text-green-800` on `white/90`
passes WCAG AA.

---

## 9. Surface Inventory

| Surface | Nav area | Notes |
|---------|----------|-------|
| `app/views/layouts/public_page.html.erb` | public | Page chrome — becomes theme-aware |
| `app/views/public_pages/show.html.erb` | public | Unchanged structurally |
| `app/views/member/pages/show.html.erb` | member | No chrome change needed |
| `app/views/admin/maintenance/page_renders/show.html.erb` | admin (Maintenance/Modules) | No chrome change needed |
| `FormFields::PageComponent` | shared | Title treatment tweak |
| `FormFields::FormComponent` | shared | Group wrapper + button upgrade |
| `FormFields::WizardComponent` | shared | Connector + secondary btn polish |
| `FormFields::BaseFieldComponent` / `resolve_input_classes` | shared | Ring offset, shadow, transition |
| `FormFields::RadioFieldComponent` | shared | Theme-derived input color + hover wrapper |
| `FormFields::CheckboxFieldComponent` | shared | Override input_classes |
| `FormFields::ToggleFieldComponent` | shared | Theme-derived checked_track color |
| `FormFields::RatingFieldComponent` | shared | Amber fill, theme focus ring |
| `FormFields::FileUploadFieldComponent` | shared | Neutral hover, theme CTA text |
| `FormFields::DividerElementComponent` | shared | Label mask bug fix |
| `FormFields::SectionElementComponent` | shared | Accent-derived linked variant |
| `FormFields::CalloutElementComponent` | shared | Accent-derived styling |
| `FormFields::QuoteElementComponent` | shared | Editorial polish |
| `FormFields::HeadingElementComponent` | shared | Tighter tracking |
| `FormFields::CardElementComponent` | shared | Shadow lift on hover |
| `FormFields::AlertElementComponent` | shared | rounded-xl + shadow |
| `FormFields::ProgressBarElementComponent` | shared | Slim track, ease-out |
| `FormFields::ButtonElementComponent` | shared | active:scale-95 |
| `app/components/concerns/theme_resolver.rb` | shared | All map changes in Section 3 |

---

## 10. Component Reuse Map

All changes are to EXISTING components. No new ViewComponent classes are created
by this spec.

| Component | Change type | Key new props/methods |
|-----------|-------------|----------------------|
| `ThemeResolver` (concern) | Enrich maps + new constants + new resolver helpers | `resolve_page_chrome_bg`, `resolve_page_chrome_header_color`, `resolve_page_chrome_desc_color`, `resolve_page_chrome_card` |
| `FormFields::PageComponent` | Heading tracking | None |
| `FormFields::FormComponent` | Group wrapper | `form_container_classes` |
| `FormFields::WizardComponent` | Connector height, secondary btn | Updates to `secondary_button_classes` |
| `FormFields::DividerElementComponent` | Bug fix + include ThemeResolver | `theme:` param, `label_bg_class` |
| `FormFields::SectionElementComponent` | Accent-derived + include ThemeResolver | `theme:` param |
| `FormFields::CalloutElementComponent` | Accent-derived + include ThemeResolver | `theme:` param |
| `FormFields::RadioFieldComponent` | Theme-derived radio classes | `radio_input_classes`, `radio_option_wrapper_classes` |
| `FormFields::CheckboxFieldComponent` | Override input_classes | Overrides `input_classes` |
| `FormFields::ToggleFieldComponent` | Theme-derived toggle | `toggle_track_classes` |
| `FormFields::RatingFieldComponent` | Amber fill, theme focus | Uses `color_palette(theme)[:ring_color]` |
| `FormFields::FileUploadFieldComponent` | Theme CTA + include ThemeResolver | `theme:` param, `dropzone_classes`, `upload_cta_classes` |

---

## 11. Tailwind & Stimulus Notes

### Tailwind

- All new palette key values are full literal class strings — no string
  interpolation, no surgery. They appear as values in the Ruby hash in
  `theme_resolver.rb`, which Tailwind v4 scans.
- The `PAGE_CHROME_*` maps follow the same pattern — literal class strings as
  hash values, scanned from `theme_resolver.rb`.
- Transitions are `transition-all duration-150` (fast, 150ms) for hover state
  changes and `transition-all duration-200` (200ms) for focus ring appearance —
  matching the existing button pattern.
- Scale micro-interactions: `active:scale-95` on all primary and gradient buttons.
  This is a `transform` utility and has no accessibility issues.
- The showcase dark background gradient uses three-stop syntax:
  `bg-gradient-to-br from-violet-950 via-violet-900 to-indigo-900` — all literal.

### Stimulus

No new Stimulus controllers. The `wizard` controller dynamically sets badge
colors and connector colors via `data-wizard-accent-color-value` (which already
passes `progress_bar_color` from `WizardComponent`). No change needed to the
wizard controller itself — it reads from the Ruby-rendered data attribute.

The `rating` controller (`app/javascript/controllers/rating_controller.js`) uses
hover/select to toggle the SVG class between the filled and unfilled state. The
controller should be updated to use `text-amber-400` instead of `text-yellow-400`
for the hover fill — this is a JS string change in the controller, which falls in
the frontend developer's lane.

---

## RETURN
ux_doc: /home/ec2-user/anysys/docs/superpowers/specs/2026-06-11-themed-templates-redesign-design.md
surfaces:
  - name: Public page chrome (layouts/public_page.html.erb)
    nav_area: public
    new_components: []
    reused_components: [ThemeResolver]
  - name: FormFields::PageComponent
    nav_area: public
    new_components: []
    reused_components: [FormFields::PageComponent]
  - name: FormFields::FormComponent
    nav_area: public
    new_components: []
    reused_components: [FormFields::FormComponent]
  - name: FormFields::WizardComponent
    nav_area: public
    new_components: []
    reused_components: [FormFields::WizardComponent]
  - name: All input/layout FormFields components (14 components)
    nav_area: public
    new_components: []
    reused_components: [FormFields::BaseFieldComponent, FormFields::RadioFieldComponent, FormFields::CheckboxFieldComponent, FormFields::ToggleFieldComponent, FormFields::RatingFieldComponent, FormFields::FileUploadFieldComponent, FormFields::DividerElementComponent, FormFields::SectionElementComponent, FormFields::CalloutElementComponent, FormFields::QuoteElementComponent, FormFields::CardElementComponent, FormFields::AlertElementComponent, FormFields::ProgressBarElementComponent, FormFields::ButtonElementComponent]
overall: READY_FOR_FRONTEND
notes: All six presets get a distinct visual personality through new PAGE_CHROME_* maps in ThemeResolver (literal Ruby hashes, Tailwind v4 scanner-safe). The BUTTON_STYLE_MAP string-surgery pattern is replaced with literal palette keys, allowing the four existing @source inline() safelist lines to be removed entirely. The divider label-mask bug is fixed by passing theme: to DividerElementComponent so the mask color matches the form background. The public chrome layout becomes fully theme-aware with per-preset background, header color, and card shell without requiring any schema or controller changes.
