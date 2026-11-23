# Slice B Media/Templates/Sanitize Implementation Plan

> **For agentic workers:** Implement independently in parallel where files do not conflict. **DO NOT commit.**

**Goal:** Replace defined?-guarded barcode/QR/template/sanitize emission with FlowchartRuntime wrappers over mature gems.

**Architecture:** Mirror Slice A (`FlowchartRuntime::Jwt` / `Cipher` / `Archive`).

**Tech Stack:** barby, rqrcode, liquid, loofah (Rails), mini_magick, RSpec

## Global Constraints

- No auto-commit
- No `defined?(Gem)` fail-open for required deps in touched generators
- Rescue wrapper errors into `ctx[:_last_error]` + return false
- en + zh-CN locale parity for removed/changed UI knobs
- Audits exit 0

### Task 1: FlowchartRuntime::Barcode + barcode_generate

**Files:** Create `app/services/flowchart_runtime/barcode.rb` + spec; modify barcode_generate_generator + spec; Gemfile `barby`; UI/locales drop `qr` symbology if listed

**Interface:**
```ruby
FlowchartRuntime::Barcode.generate(data, format: :code128, output: :png, width: 2, height: 100, margin: 10, include_text: true) -> String
# raises FlowchartRuntime::Barcode::Error
# formats: code128 code39 ean13 ean8 upca itf codabar (NO qr)
# outputs: png svg jpg base64
```

### Task 2: FlowchartRuntime::QrCode + qr_code_generate

**Files:** Create `app/services/flowchart_runtime/qr_code.rb` + spec; modify qr_code_generate_generator + spec; drop logoExpression from schema/UI/locales

**Interface:**
```ruby
FlowchartRuntime::QrCode.generate(data, size: 4, level: :m, margin: 4, color_dark: "#000000", color_light: "#FFFFFF", output: :png) -> String
# raises FlowchartRuntime::QrCode::Error
# outputs: png svg base64 ascii
```

### Task 3: FlowchartRuntime::Template + template_render

**Files:** Create `app/services/flowchart_runtime/template.rb` + spec; modify template_render_generator + spec; Gemfile `liquid`; trim engine enum to liquid (+ maybe erb via ERB stdlib if already supported without defined?)

**Interface:**
```ruby
FlowchartRuntime::Template.render(source, variables = {}, engine: :liquid) -> String
# raises FlowchartRuntime::Template::Error
# engines: liquid only (breaking: remove handlebars/mustache/haml)
```

Also update `format_string_generator` Liquid path to call the same wrapper if it emits `defined?(Liquid)`.

### Task 4: sanitize_input → Loofah always

**Files:** modify sanitize_input_generator + spec; no new gem (loofah via Rails)

Emit `Loofah.fragment(...).scrub!(:prune).to_s` (or thin `FlowchartRuntime::Sanitize.html`) — prefer thin wrapper for consistency:
```ruby
FlowchartRuntime::Sanitize.html(string) -> String
```

### Task 5: Final greps + audits + focused specs

Grep forbid defined?(Barby|RQRCode|Liquid|Loofah|MiniMagick|CodeGenerators::Support) in touched files. Audits 0.
