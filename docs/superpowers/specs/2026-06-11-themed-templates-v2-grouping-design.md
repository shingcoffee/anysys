# Themed Templates v2 — Grouping & Spacing Design Spec

**Date:** 2026-06-11  
**Focus:** Field grouping, spacing rhythm, grid alignment — visual polish round 2  
**Implementation surfaces:** `theme_resolver.rb`, `FormFields::*Component` templates, `page_content_generator.rb`, `public_page.html.erb`, `member/pages/show.html.erb`  
**Out of scope:** Generator DOM-nesting changes, schema, routes, controllers, new Stimulus controllers

---

## 1. Screenshot Critique (grouping/spacing lens)

All four themes share the same structural problems with different severity.

### 1.1 modern (indigo, space-y-5, outline inputs)

**Desktop observation:**
- "Attendee Information" fieldset renders as a legend + grey divider line only. The card that follows it (Full Name / Email pair) is not visually attached to it — the gap between legend and first field equals the gap between every other pair. A reader cannot immediately perceive which fields belong to "Attendee Information" and which to the next section.
- The Card element (inside section 1) gets the same vertical gap as adjacent form rows, making it blend into the field list.
- "Event Details" legend appears ~20 px below the Promo Code field and ~20 px above "Event Name / Type" — identical spacing on both sides. This violates the proximity principle: the legend should sit closer to its own children (8 px gap below) than to the preceding section's last field (32 px gap above).
- Half-width field pairs (Full Name + Email, Phone + Organization, Number of Guests + Registration Type, Meal Preference + T-Shirt Size): on mobile the grid renders both fields at `col-span-6` (half viewport), producing narrow inputs at 375 px. The label "Organization / Company" wraps to 2 lines, but the adjacent "Phone Number" label stays on 1 line, creating a top-misaligned input row — the phone input starts 18 px higher than the Organization input.
- Checkbox rows ("Dietary Restrictions…", "I agree to…") share the same `space-y-5` gap as text inputs above them, so the "Special Requests or Notes" textarea appears equally related to the checkbox as it does to "I agree to…" even though those two checkboxes semantically bracket different ideas.

**Mobile observation:**
- Half-width fields remain `col-span-6` at 375 px. The combined width per field is ~155 px, barely enough for "Registration Type (General, VIP, Student, Press)" label which wraps to 4 lines, pushing that select input far below its paired "Number of Guests" input.
- No responsive collapse to `col-span-12` on mobile is emitted by the generator for these specific fields (only the content-area provides `space-y`). The root issue is `responsive_col_span` only promotes up if the field author set `responsive_widths.mobile`; default is to remain half.

### 1.2 minimalist (slate, space-y-3, underline inputs, uppercase labels)

**Desktop:**
- `space-y-3` (12 px) is very tight. The section legend "Attendee Information" receives the same 12 px gap before and after as between two adjacent text fields. The result is that sections feel like ordinary labels — they do not visually "start" anything.
- The divider between sections is an `<hr>` with `my-4` (16 px). At `space-y-3` spacing, the divider adds only a marginally bigger visual pause. Still not enough to read as "section boundary."
- Uppercase label style correctly reads as secondary text, but with 12 px between rows the form is dense and legible only when scrolled slowly.
- Checkbox lines are particularly cramped: `mb-4` on the wrapper adds 16 px, but the wrapping `space-y-3` overrides, keeping rows at 12 px.

### 1.3 elegant (violet, space-y-8, outline inputs, warm bg, serif font)

**Desktop:**
- `space-y-8` (32 px) is the most generous spacing. The form breathes well. However section legends still get the same 32 px above and below, creating symmetric white space that does not anchor the legend to its fields.
- The section → first field gap (32 px) is identical to the last field → next section gap (32 px). Reversed proximity: the legend appears to "float" between groups rather than lead its group.
- Half-width pairs still misalign when labels wrap — "Registration Type (General, VIP, Student, Press)" creates a 2-line label while "Number of Guests" is 1 line, displacing the two inputs vertically.
- The elegant warm background makes the Card element's white surface pop cleanly — this is actually a strength of this theme but the Card gets `space-y-8` spacing above/below which is too generous.

**Mobile:**
- Same half-width collapse issue as modern. The 375-px viewport with `col-span-6` is unworkable for long labels.

### 1.4 showcase (violet, space-y-8, uppercase labels, full-width form on dark bg)

**Desktop:**
- Full-width form on a deep purple gradient. The wide canvas amplifies the rhythm problem: the "Event Details" section legend appears mid-scroll with 32 px above and 32 px below, with nothing visually differentiating it from a field label at distance.
- Uppercase labels at `space-y-8` give a sense of airiness, but long-label half-width pairs produce the worst misalignment here because the form is very wide — the two inputs in a pair are further apart horizontally, making the vertical offset more jarring.

### 1.5 bold (rose, space-y-5, filled inputs, full-radius)

- The `border-t-4 border-rose-500` card top-border on the PAGE CHROME is a strong visual anchor — good design.
- Section legends are readable at `space-y-5` but still float symmetrically.
- The "Require accessibility accommodations?" label (a checkbox rendered without a wrapper input field) followed immediately by "How Did You Hear About This Event?" produces two adjacent text lines with no visual break — looks like a fragment.

### 1.6 Common findings summary

| Issue | Severity | Affected presets |
|---|---|---|
| Section legend has equal spacing above/below (no proximity anchoring) | Critical | all 6 |
| Half-width label wrapping causes input top-misalignment | Critical | all (worse on wide forms) |
| No mobile collapse for half-width pairs | High | all |
| Divider spacing undifferentiated from field spacing | High | minimalist, modern |
| Checkbox wrapper has its own `mb-4` fighting space-y | Medium | all |
| Section has no visual containment beyond a legend line | Medium | all |
| Label→input gap is fixed 1px (mb-1/mb-2) regardless of theme personality | Low | all |
| Checkbox label text doesn't respond to theme label_style | Low | all |

---

## 2. Spacing Rhythm System

### 2.1 Design principles

1. **Proximity rule:** A section heading must sit closer to the first field that follows it than to the last field that precedes it. Ratio target: gap-before ≥ 2.5× gap-after.
2. **Hierarchy scale:** Three distances — field-to-field, section-entry (before heading), section-exit (after heading / before first field).
3. **Section elements self-manage their entry margin.** Because `SectionElementComponent` renders as a flat DOM sibling, it emits its own top margin to create the large "section entry" gap. The `space-y-*` container then adds a uniform gap between the section element and the next sibling; the section element offsets this by reducing its own bottom margin or by the next sibling's mt being minimal.

The practical implementation: keep `space-y-*` as the base rhythm for field-to-field. `SectionElementComponent` adds an extra top margin via its outer `<fieldset>` to create the "section entry" gap. The heading-to-first-field gap uses the section's own reduced `mb-*`.

### 2.2 Scale definition per `field_spacing` value

#### tight (minimalist preset — space-y-3 = 12 px)

| Gap | Role | Classes |
|---|---|---|
| 12 px | field → field | `space-y-3` on container (existing) |
| 28 px | last field → section legend | `mt-6` on fieldset (adds 24 px + 4 px from space-y-3 = 28 px) |
| 8 px | section legend → first field | `mb-2` on fieldset |
| 12 px | divider self-spacing | `my-3` on divider wrapper (down from `my-4`) |
| 4 px | label → input | label class `mb-1` (unchanged) |
| 2 px | input → help text | help `mt-0.5` |

#### normal (modern, bold presets — space-y-5 = 20 px)

| Gap | Role | Classes |
|---|---|---|
| 20 px | field → field | `space-y-5` on container (existing) |
| 44 px | last field → section legend | `mt-6` on fieldset (adds 24 px + 20 px from space-y-5 = 44 px) |
| 10 px | section legend → first field | `mb-2.5` on fieldset |
| 20 px | divider self-spacing | `my-5` on divider wrapper |
| 4 px | label → input | label class `mb-1` (unchanged) |
| 4 px | input → help text | help `mt-1` |

#### relaxed (elegant, showcase, playful presets — space-y-8 = 32 px)

| Gap | Role | Classes |
|---|---|---|
| 32 px | field → field | `space-y-8` on container (existing) |
| 64 px | last field → section legend | `mt-8` on fieldset (adds 32 px + 32 px from space-y-8 = 64 px) |
| 12 px | section legend → first field | `mb-3` on fieldset |
| 24 px | divider self-spacing | `my-6` on divider wrapper |
| 4 px | label → input | label class `mb-1` (unchanged for default/bold labels) |
| 6 px | label → input (uppercase) | label class `mb-1.5` — uppercase labels have more visual weight, needs slightly more separation |
| 4 px | input → help text | help `mt-1` |

The section fieldset must NOT carry bottom margin in the DOM — the `space-y-*` container handles field-to-field gap. Only `mt-*` is added.

### 2.3 Rhythm classes — new ThemeResolver maps

Two new maps are needed to distribute the section and divider spacing per `field_spacing` key:

```ruby
SECTION_SPACING_MAP = {
  "tight"   => { mt: "mt-6",  mb: "mb-2"   },
  "normal"  => { mt: "mt-6",  mb: "mb-2.5" },
  "relaxed" => { mt: "mt-8",  mb: "mb-3"   }
}.freeze

DIVIDER_SPACING_MAP = {
  "tight"   => "my-3",
  "normal"  => "my-5",
  "relaxed" => "my-6"
}.freeze
```

Additionally, `FormComponent` currently applies `space-y-4` hardcoded inside the content `<div>` wrapper (line 16 of `form_component.html.erb`). That must be replaced with `resolve_field_spacing(theme)` — same as ContentComponent already does.

---

## 3. Field Grouping — Per-Preset Section Treatment

Sections cannot contain fields in the DOM. The visual containment approach is:

**Method A (spacing-only, all presets):** The extra `mt-*` before the section heading creates a large visual gap that "opens" a new group. The tight `mb-*` after the heading "closes the gap" to its fields. This creates strong proximity without DOM changes.

**Method B (left accent tick, optional on modern/bold/showcase):** For these presets, add a `border-l-2 pl-3` left border in the section's accent color as a group marker. This is a CSS-only container cue that doesn't wrap fields.

**Method C (subtle background band, elegant only):** Not achievable without DOM wrapping. Out of scope.

### Per-preset section fieldset class specs

The `<fieldset>` element in `section_element_component.html.erb` (non-linked variant) currently has: `class="mb-8"`.

**v2 classes replace `mb-8` with the spacing map values + add the border treatment where applicable.**

Note: The first section on the page should NOT get the `mt-*` top margin (it would add unwanted space at the top of the form). However, detecting "first section" requires DOM knowledge the component doesn't have. A pragmatic approach: always emit `mt-*` and compensate with a negative top margin on the container's first child using CSS selector `[data-field-id]:first-child fieldset { margin-top: 0 }` — but this is custom CSS and violates the Tailwind-only constraint. Instead: always emit `mt-*`; accept that the first section on a form will have extra top padding. The form's own top `p-*` absorbs most of this. This is acceptable.

#### modern (field_spacing: normal, primary: indigo)

```
<fieldset class="mt-6 mb-2.5 pl-3 border-l-2 border-indigo-300">
  <legend class="text-lg font-semibold text-gray-900 pb-1.5 w-full">
    ...title
  </legend>
  ...description
</fieldset>
```

The `border-b` divider under the legend is removed. The accent left border replaces it as group marker. Bottom border on the legend is visual clutter when a left border already marks the group.

#### minimalist (field_spacing: tight, primary: slate)

```
<fieldset class="mt-6 mb-2">
  <legend class="text-xs font-semibold text-gray-500 uppercase tracking-widest pb-1.5 border-b border-gray-200 w-full">
    ...title
  </legend>
  ...description
</fieldset>
```

No accent border (minimalist avoids decorative marks). Keep bottom border on legend but tighten it.

#### bold (field_spacing: normal, primary: rose)

```
<fieldset class="mt-6 mb-2.5 pl-3 border-l-2 border-rose-400">
  <legend class="text-lg font-bold text-gray-900 pb-1.5 w-full">
    ...title
  </legend>
  ...description
</fieldset>
```

Bold variant uses `font-bold` on the legend (matching `label_style: bold` personality).

#### elegant (field_spacing: relaxed, primary: violet)

```
<fieldset class="mt-8 mb-3">
  <legend class="text-lg font-semibold text-violet-900 pb-2 border-b border-gray-200 w-full font-serif">
    ...title
  </legend>
  ...description
</fieldset>
```

Elegant keeps the bottom border on the legend (traditionally serif/editorial). No left tick — that conflicts with the elegant aesthetic. Font-serif matches the form's `font_family: serif` theme key.

#### playful (field_spacing: relaxed, primary: emerald)

```
<fieldset class="mt-8 mb-3 pl-3 border-l-2 border-emerald-400">
  <legend class="text-lg font-semibold text-gray-900 pb-1.5 w-full">
    ...title
  </legend>
  ...description
</fieldset>
```

#### showcase (field_spacing: relaxed, primary: violet)

```
<fieldset class="mt-8 mb-3 pl-3 border-l-2 border-violet-400">
  <legend class="text-xs font-semibold text-gray-500 uppercase tracking-widest pb-1.5 w-full">
    ...title
  </legend>
  ...description
</fieldset>
```

Showcase uses uppercase legend (matching `label_style: uppercase`) to unify the header/body typographic register.

### How to implement theme-specific section classes in the component

`SectionElementComponent` receives `theme: {}`. Add a `section_fieldset_classes` helper and a `section_legend_classes` helper that reads `field_spacing`, `primary_color`, `border_radius` (via `detect_preset` is acceptable here as the component already has access to ThemeResolver). The helpers return the exact strings above.

The field_spacing → margin resolution goes through a new helper in ThemeResolver:

```ruby
def resolve_section_top_margin(theme)
  spacing = resolve_theme(theme)["field_spacing"] || "normal"
  SECTION_SPACING_MAP.dig(spacing, :mt) || "mt-6"
end

def resolve_section_bottom_margin(theme)
  spacing = resolve_theme(theme)["field_spacing"] || "normal"
  SECTION_SPACING_MAP.dig(spacing, :mb) || "mb-2.5"
end
```

The per-preset left border and legend weight are determined by `detect_preset(theme)`:

```ruby
SECTION_BORDER_MAP = {
  "modern"     => "pl-3 border-l-2 border-indigo-300",
  "minimalist" => "",
  "bold"       => "pl-3 border-l-2 border-rose-400",
  "elegant"    => "",
  "playful"    => "pl-3 border-l-2 border-emerald-400",
  "showcase"   => "pl-3 border-l-2 border-violet-400"
}.freeze

SECTION_LEGEND_EXTRA_MAP = {
  "modern"     => "",
  "minimalist" => "text-xs font-semibold text-gray-500 uppercase tracking-widest",
  "bold"       => "font-bold",
  "elegant"    => "text-violet-900 font-serif",
  "playful"    => "",
  "showcase"   => "text-xs font-semibold text-gray-500 uppercase tracking-widest"
}.freeze
```

For non-preset (custom) themes, `detect_preset` returns nil — fall back to spacing-only (no border, no legend override). The section legend base class for non-preset: `"text-lg font-semibold text-gray-900 pb-2 border-b border-gray-200 w-full"`.

---

## 4. Grid Alignment Fix (half-width pairs)

### Problem

`render_field_row` emits:
```html
<div class="grid grid-cols-12 gap-x-4">
  <div class="col-span-6">
    <!-- field with label wrapping to 2 lines -->
  </div>
  <div class="col-span-6">
    <!-- field with 1-line label: input starts 18px higher -->
  </div>
</div>
```

When one label wraps to 2 lines and the sibling does not, the inputs in each column start at different vertical positions.

### Solution A — items-end alignment (preferred)

Change the grid row div to use `items-end` so all field wrappers in the same grid row align their **bottoms** (the input edge) rather than their tops. Label text flows up from the input.

```
before: <div class="grid grid-cols-12 gap-x-4">
after:  <div class="grid grid-cols-12 gap-x-4 items-end">
```

This keeps multi-line labels readable (they grow upward from the input) and aligns all inputs across a row. It is a single class addition to the string in `render_field_row`.

The visual result: for "Number of Guests" (1-line label) and "Registration Type (General, VIP, Student, Press)" (3-line label), the select inputs sit flush at the bottom, label text floats above each input independently.

**Tailwind-only, no JS, no DOM nesting change.**

### Solution B — min-height on labels (fallback note)

An alternative would be `min-h-[3rem]` on the label element so all labels reserve space for 2 lines. This is fragile (would need to be 3rem for some labels in bold/lg input themes). Solution A is preferred.

### Mobile collapse

Currently `responsive_col_span` preserves the author's `width: "half"` on mobile unless `responsive_widths.mobile` is set. For the rendering layer, add a universal mobile fallback: if a field has no explicit `responsive_widths.mobile` value, default mobile to `"full"` (col-span-12) when the field is in a multi-field row. This is a change to `responsive_col_span` in `page_content_generator.rb`:

```ruby
def responsive_col_span(field)
  desktop_width = field["width"] || "full"
  responsive = field["responsive_widths"] || {}

  # Default mobile to full-width for all fields in multi-field rows
  # unless the author has explicitly set a mobile responsive width.
  mobile_width  = responsive["mobile"] || "full"
  tablet_width  = responsive["tablet"] || desktop_width

  classes = []
  classes << (COL_SPAN_CLASSES[mobile_width] || "col-span-12")
  classes << "md:#{COL_SPAN_CLASSES[tablet_width] || 'col-span-12'}" if tablet_width != mobile_width
  classes << "lg:#{COL_SPAN_CLASSES[desktop_width] || 'col-span-12'}" if desktop_width != tablet_width
  classes.join(" ")
end
```

Current code: `mobile_width = responsive["mobile"] || responsive["tablet"] || desktop_width`  
New code: `mobile_width = responsive["mobile"] || "full"`

This is the only line that changes. The fallback-to-tablet logic is removed for mobile; tablet remains as a bridge to desktop. Result: a half-width pair renders as two stacked full-width fields on mobile by default, eliminating the narrow 155-px input problem entirely.

---

## 5. Exact ThemeResolver Map Changes (full literal Ruby additions)

Add these constants to `ThemeResolver` in `app/components/concerns/theme_resolver.rb`. Insert them after the existing `FIELD_SPACING_MAP` definition:

```ruby
SECTION_SPACING_MAP = {
  "tight"   => { mt: "mt-6",  mb: "mb-2"   },
  "normal"  => { mt: "mt-6",  mb: "mb-2.5" },
  "relaxed" => { mt: "mt-8",  mb: "mb-3"   }
}.freeze

DIVIDER_SPACING_MAP = {
  "tight"   => "my-3",
  "normal"  => "my-5",
  "relaxed" => "my-6"
}.freeze

SECTION_BORDER_MAP = {
  "modern"     => "pl-3 border-l-2 border-indigo-300",
  "minimalist" => "",
  "bold"       => "pl-3 border-l-2 border-rose-400",
  "elegant"    => "",
  "playful"    => "pl-3 border-l-2 border-emerald-400",
  "showcase"   => "pl-3 border-l-2 border-violet-400"
}.freeze

SECTION_LEGEND_EXTRA_MAP = {
  "modern"     => "",
  "minimalist" => "text-xs font-semibold text-gray-500 uppercase tracking-widest",
  "bold"       => "font-bold",
  "elegant"    => "text-violet-900 font-serif",
  "playful"    => "",
  "showcase"   => "text-xs font-semibold text-gray-500 uppercase tracking-widest"
}.freeze
```

Add these resolver methods to the `private` section after `resolve_field_spacing`:

```ruby
def resolve_section_top_margin(theme)
  spacing = resolve_theme(theme)["field_spacing"] || "normal"
  SECTION_SPACING_MAP.dig(spacing, :mt) || "mt-6"
end

def resolve_section_bottom_margin(theme)
  spacing = resolve_theme(theme)["field_spacing"] || "normal"
  SECTION_SPACING_MAP.dig(spacing, :mb) || "mb-2.5"
end

def resolve_section_border(theme)
  preset = detect_preset(theme)
  preset ? (SECTION_BORDER_MAP[preset] || "") : ""
end

def resolve_section_legend_extra(theme)
  preset = detect_preset(theme)
  preset ? (SECTION_LEGEND_EXTRA_MAP[preset] || "") : ""
end

def resolve_divider_spacing(theme)
  spacing = resolve_theme(theme)["field_spacing"] || "normal"
  DIVIDER_SPACING_MAP[spacing] || "my-5"
end
```

---

## 6. Per-Component Before→After Class Specs

### 6.1 SectionElementComponent (non-linked variant)

**File:** `app/components/form_fields/section_element_component.html.erb`

Before:
```erb
<fieldset class="mb-8">
  <legend class="text-lg font-semibold <%= neutral(:strong_text) %> pb-2 border-b <%= neutral(:subtle_border) %> w-full"><%= title %></legend>
  <% if description.present? %>
    <p class="mt-1.5 text-sm <%= neutral(:muted_text) %>"><%= description %></p>
  <% end %>
</fieldset>
```

After:
```erb
<fieldset class="<%= section_fieldset_classes %>">
  <legend class="<%= section_legend_classes %>"><%= title %></legend>
  <% if description.present? %>
    <p class="mt-1 text-sm <%= neutral(:muted_text) %>"><%= description %></p>
  <% end %>
</fieldset>
```

**File:** `app/components/form_fields/section_element_component.rb`

Add two helper methods:

```ruby
def section_fieldset_classes
  top    = resolve_section_top_margin(@theme)
  bottom = resolve_section_bottom_margin(@theme)
  border = resolve_section_border(@theme)
  [top, bottom, border].reject(&:blank?).join(" ")
end

def section_legend_classes
  extra = resolve_section_legend_extra(@theme)
  base  = if extra.include?("text-xs")
            # uppercase variant — suppress the default text-lg
            ""
          else
            "text-lg font-semibold #{neutral(:strong_text)} pb-1.5 w-full"
          end
  # Elegant gets a bottom border; others with left-border do not
  border_b = resolve_section_border(@theme).blank? && !extra.include?("text-xs") ?
               "border-b #{neutral(:subtle_border)}" : ""
  [base, border_b, extra].reject(&:blank?).join(" ")
end
```

**Linked variant (pl-4 border-l-2):** No change in v2 — the linked variant is already a left-bordered inline section marker. Only its `mb-6` should move to the new spacing map value (`mb-2` / `mb-2.5` / `mb-3` per spacing) while keeping the top margin at `mt-4` / `mt-5` / `mt-6` for the three scales respectively. Add a second set of keys to `SECTION_SPACING_MAP` if desired, or simply hard-code the linked variant with `mt-4 mb-2` as an acceptable constant.

### 6.2 DividerElementComponent

**File:** `app/components/form_fields/divider_element_component.rb`

Current `SPACING` map:
```ruby
SPACING = {
  'sm' => 'my-2',
  'md' => 'my-4',
  'lg' => 'my-8'
}.freeze
```

The generator always emits `spacing: '"md"'`. The `my-4` value (16 px) does not respond to the form's `field_spacing` theme setting. Change the `spacing_class` method:

Before:
```ruby
def spacing_class
  SPACING[spacing] || SPACING['md']
end
```

After:
```ruby
def spacing_class
  return SPACING[spacing] unless spacing == 'md'
  resolve_divider_spacing(@theme)
end
```

This preserves explicit `sm`/`lg` spacing overrides while making the default `md` respond to the theme's field_spacing value. DividerElementComponent already includes ThemeResolver via BaseElementComponent.

**Template:** No change needed.

### 6.3 HeadingElementComponent

The heading element is used as an intermediate-level structural title within sections. It has no top margin — it sits in the flow controlled by `space-y-*`. Add a top margin consistent with "heading is starting a sub-group" — slightly smaller than a full section entry:

**File:** `app/components/form_fields/heading_element_component.rb`

Add to the `heading_classes` method (or create a new `wrapper_classes` method and update the template to use a wrapping div):

```ruby
HEADING_TOP_MARGIN_MAP = {
  "tight"   => "mt-2",
  "normal"  => "mt-3",
  "relaxed" => "mt-4"
}.freeze

def wrapper_margin
  spacing = resolve_theme(@theme)["field_spacing"] || "normal"
  HEADING_TOP_MARGIN_MAP[spacing] || "mt-3"
end
```

**Template:** The wrapper div already exists with a hardcoded `mb-4`. Replace with `wrapper_margin`:

Before (current template):
```erb
<div class="mb-4">
  <%= content_tag heading_tag, text, class: heading_classes %>
</div>
```

After:
```erb
<div class="<%= wrapper_margin %>">
  <%= content_tag heading_tag, text, class: heading_classes %>
</div>
```

### 6.4 ContentComponent / grid wrapper (field rows)

**File:** `app/services/page_content_generator.rb`, method `render_field_row`

Current:
```ruby
%(<div class="grid grid-cols-12 gap-x-4">\n      #{cells}\n      </div>)
```

After:
```ruby
%(<div class="grid grid-cols-12 gap-x-4 items-end">\n      #{cells}\n      </div>)
```

Single class addition. No other changes to this method.

**File:** `app/services/page_content_generator.rb`, method `responsive_col_span`

Current line 4 of the method body:
```ruby
mobile_width = responsive["mobile"] || responsive["tablet"] || desktop_width
```

After:
```ruby
mobile_width = responsive["mobile"] || "full"
```

**File:** `app/components/form_fields/form_component.html.erb`, line 16

Current:
```erb
<div class="space-y-4">
```

After:
```erb
<div class="<%= resolve_field_spacing(theme) %>">
```

The `FormComponent` class already includes `ThemeResolver` and `theme` is accessible — no Ruby class change needed.

### 6.5 BaseFieldComponent — label and help-text spacing

**File:** `app/components/form_fields/base_field_component.rb`

The `wrapper_classes` method currently returns `"mb-4 w-full"`. In v2, field spacing is handled by the container's `space-y-*` — the per-field `mb-4` creates inconsistent double-spacing with the `space-y-*` parent. Remove `mb-4` from the field wrapper.

Before:
```ruby
def wrapper_classes
  base = "mb-4"
  case width
  when "half" then "#{base} w-1/2 inline-block align-top pr-2"
  when "third" then "#{base} w-1/3 inline-block align-top pr-2"
  else "#{base} w-full"
  end
end
```

After:
```ruby
def wrapper_classes
  "w-full"
end
```

Note: The `w-1/2 inline-block` branches for `"half"` and `"third"` width are also removed because in v2 half-width layout is controlled by the 12-column grid wrapper from the generator, not by inline-block. Any field rendered solo (single-field row) still gets `w-full`.

**Help text:** The `html_attributes[:help_text]` pattern currently used in `radio_field_component.html.erb` uses `mt-1 text-sm text-gray-500` hardcoded. Keep this in v2 (low priority).

### 6.6 CheckboxFieldComponent — wrapper mb removal

**File:** `app/components/form_fields/checkbox_field_component.rb`

Same issue as BaseFieldComponent — `mb-4` in wrapper_classes double-spaces with `space-y-*`.

Before:
```ruby
def wrapper_classes
  base = "mb-4"
  case width
  when "half" then "#{base} w-1/2 inline-block align-top pr-2"
  when "third" then "#{base} w-1/3 inline-block align-top pr-2"
  else "#{base} w-full"
  end
end
```

After:
```ruby
def wrapper_classes
  "w-full"
end
```

### 6.7 Member view chrome (member/pages/show.html.erb)

Current shell:
```erb
<div class="card overflow-x-auto">
  <div class="px-6 py-4 border-b border-border-subtle">
    <h2 class="section-header"><%= @page.name %></h2>
    ...
  </div>
  <div class="p-6">
    ...
  </div>
</div>
```

The admin `.card` wrapper is correct for the member shell's context (it sits inside the member dashboard layout), but it strips all themed chrome from the rendered form. The `PageComponent` inside renders its own `bg-*`, `shadow-*`, `rounded-*`, and `p-*` correctly — but the outer `.card` adds a second layer of white background and a separate title header, making the page title appear twice (once in the member shell header, once as the PageComponent title if `show_title` were true — currently it's false so only the shell header shows).

The problem: the member shell applies `p-6` padding inside `.card`, then `PageComponent` applies its own `p-6`/`p-8` padding. The form content has double padding on mobile.

**v2 design: remove the inner p-6 wrapper and let PageComponent breathe.** The member page shell becomes a chromatic frame that sets the audience context.

After:
```erb
<%
  # Resolve the theme so we can pick a chromatic accent for the shell header.
  _theme = @page.configuration_json&.dig("theme") || {}
  _preset = helpers.detect_preset(_theme) rescue nil
  _header_color = ThemeResolver::PAGE_CHROME_HEADER_MAP[_preset] || "text-gray-900"
%>
<div class="card overflow-hidden">
  <div class="px-6 py-4 border-b border-border-subtle">
    <h2 class="section-header <%= _header_color %>"><%= @page.name %></h2>
    <% if @page.description.present? %>
      <p class="mt-1 text-body-sm"><%= @page.description %></p>
    <% end %>
  </div>
  <% if @content.present? %>
    <%= render inline: @content %>
  <% else %>
    <div class="p-6">
      <p class="text-body-sm text-text-muted">This page has no content to render yet.</p>
    </div>
  <% end %>
</div>
```

Changes:
- Remove `<div class="p-6">` wrapper around `render inline: @content` — the `PageComponent` provides its own padding.
- Add `_header_color` class to the `h2` so the shell header text color matches the theme accent.
- Change `overflow-x-auto` to `overflow-hidden` — the card should clip PageComponent's shadow/radius at the card boundary.
- Move the description into the shell header (it was already there, kept).
- The empty state retains its own `p-6` for layout purposes.

Note: `helpers.detect_preset` is accessible from ERB views. If not, extract the logic into a presenter or helper. The simplest approach: call `ThemeResolver::THEME_PRESETS.each { |name, preset| break name if preset.all? { |k,v| _theme[k] == v } }` inline, or add a `page_theme_preset` helper method to `ApplicationHelper` that accepts a page object.

---

## 7. Responsive Notes

### 7.1 Mobile (< md, ~375 px)

- With the `mobile_width = "full"` change to `responsive_col_span`, all half/third/quarter-width fields collapse to `col-span-12` on mobile by default. Fields authored with explicit `responsive_widths.mobile` keep their setting.
- Section legend left borders (`border-l-2 pl-3`) are preserved at all breakpoints — they remain readable at 375 px.
- The form container padding on mobile: `FormPageComponent` resolves `form_padding` from the theme (compact `p-4`, normal `p-6`, spacious `p-8`, generous `p-10`). No mobile-specific override needed — the existing padding keys are already appropriately sized.
- Member shell: `<div class="card overflow-hidden">` — the `.card` class is a project utility class (not raw Tailwind). It should already be responsive. No change needed.

### 7.2 Tablet (md, ~768 px)

- With `tablet_width = responsive["tablet"] || desktop_width`, half-width fields stay at half-width on tablet unless the author overrides. This is correct behavior.
- `items-end` on the grid row works correctly at all breakpoints.

### 7.3 The `items-end` interaction with checkbox rows

Checkbox fields rendered solo (single-field row, no grid wrapper) are unaffected. Checkboxes in a multi-field grid row get `items-end` alignment from the grid wrapper — their wrapper is `w-full` (single column) so alignment has no effect on a solo checkbox in a row. If a checkbox is ever placed in a 2-column row with a text input, `items-end` would align the checkbox's bottom edge with the text input's bottom edge. This is visually correct.

---

## 8. Summary of All Changes (Implementation Checklist)

### ThemeResolver (`app/components/concerns/theme_resolver.rb`)
- Add `SECTION_SPACING_MAP`, `DIVIDER_SPACING_MAP`, `SECTION_BORDER_MAP`, `SECTION_LEGEND_EXTRA_MAP` constants (full literals in section 5)
- Add resolver methods: `resolve_section_top_margin`, `resolve_section_bottom_margin`, `resolve_section_border`, `resolve_section_legend_extra`, `resolve_divider_spacing`

### FormFields::SectionElementComponent
- `section_element_component.html.erb`: Replace hardcoded `mb-8` fieldset class and legend class with helper-driven classes; remove `border-b` from legend (it's now conditional per preset)
- `section_element_component.rb`: Add `section_fieldset_classes` and `section_legend_classes` private methods

### FormFields::DividerElementComponent
- `divider_element_component.rb`: Change `spacing_class` method to call `resolve_divider_spacing(@theme)` when `spacing == 'md'`

### FormFields::HeadingElementComponent
- `heading_element_component.rb`: Add `HEADING_TOP_MARGIN_MAP` and `wrapper_margin` method
- `heading_element_component.html.erb`: Wrap the `content_tag` in a `<div class="<%= wrapper_margin %>">` (template must be examined for current structure — if it only has a single tag, add the wrapper div)

### FormFields::BaseFieldComponent
- `base_field_component.rb`: Remove `mb-4` from `wrapper_classes`; remove `w-1/2 inline-block` / `w-1/3 inline-block` branches (grid handles column layout)

### FormFields::CheckboxFieldComponent
- `checkbox_field_component.rb`: Remove `mb-4` from `wrapper_classes`; remove `w-1/2 inline-block` branch

### FormFields::FormComponent
- `form_component.html.erb`: Line 16 `<div class="space-y-4">` → `<div class="<%= resolve_field_spacing(theme) %>">`

### PageContentGenerator (`app/services/page_content_generator.rb`)
- `render_field_row` method: Add `items-end` to the grid div class string
- `responsive_col_span` method: Change `mobile_width` default from `responsive["tablet"] || desktop_width` to `"full"`

### Member view (`app/views/member/pages/show.html.erb`)
- Remove `<div class="p-6">` wrapper around `render inline: @content`
- Add theme-aware accent color to the shell header `h2`
- Change `overflow-x-auto` to `overflow-hidden`

---

## 9. Explicit No-Change List

The following are intentionally unchanged in v2:

- All six `THEME_PRESETS` hash values — no theme key values change; the existing JSON stored in pages continues to work
- `FIELD_SPACING_MAP` keys and values (`space-y-3` / `space-y-5` / `space-y-8`) — spacing is still driven by this map
- `ContentComponent` — no change; the `space-y-*` wrapper class is still the baseline rhythm container
- All six `PAGE_CHROME_*` maps — public page chrome is unchanged
- Generator DOM structure — no new nesting of fields inside sections
- All other `FormFields::*Component` templates not listed above
- Input styles, focus rings, button styles, select chevron behavior — not in scope for this round
- `LABEL_STYLE_MAP` — label classes are unchanged (the `uppercase tracking-widest mb-2` variant already adds `mb-2`)
- Radio field option wrapper classes — unchanged
- Toggle/switch component — unchanged
- Any spec files — the spec files for affected components will need updates to reflect the removed `mb-4` behavior (stale test policy applies)
- `RADIUS_MAP`, `FONT_MAP`, `INPUT_STYLES`, `FORM_BG_MAP`, `FORM_SHADOW_MAP`, `FORM_BORDER_MAP`, `BUTTON_STYLE_MAP` — all unchanged

---

## 10. Interaction Flow (member and public audience)

This is a visual-only polish — no new user flows. Existing flows are unchanged. The before/after experience for a user filling out a form:

**Before:** Scan down a long form; all inter-element gaps are uniform `space-y-*`; sections are hard to locate; half-width fields on mobile are unusably narrow.

**After:** Section headings are clearly anchored to their group (large gap above, small gap below); sections are visually distinct with left-border accents (modern/bold/playful/showcase) or enhanced border-bottom legends (elegant); mobile fields stack full-width by default; pairs of inputs in a row align bottoms so multi-line labels don't displace inputs.
