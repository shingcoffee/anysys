# Flowchart Generators — Slice B (Media Codes + Templates + Sanitize)

**Date:** 2026-08-03  
**Status:** Approved for implementation (controller decision — no human confirmation gate)  
**Inherits:** Slice A decisions (thin FlowchartRuntime wrappers, direct gem deps, breaking OK with regenerate, no auto-commit)

## Decisions

| Topic | Choice |
|-------|--------|
| Architecture | Same as Slice A — generators emit thin `FlowchartRuntime::*` calls |
| Barcode | `FlowchartRuntime::Barcode` over **barby** + chunky_png PNG/SVG; JPG via mini_magick |
| QR | `FlowchartRuntime::QrCode` over **rqrcode** (already direct Gemfile dep) |
| Barcode `qr` symbology | **Removed** — use `qr_code_generate` step |
| QR `logoExpression` | **Removed** — `CodeGenerators::Support` does not exist (dead path) |
| Templates | `FlowchartRuntime::Template` over **liquid** only; drop Handlebars/Mustache/Haml `defined?` branches |
| Sanitize | Emit Loofah always (Rails already depends on loofah); no `defined?(Loofah)` fail-open |
| Errors | Rescue wrapper `Error` / transport → `ctx[:_last_error]` + `false` |
| Regen | Flowchart save / `rake flowcharts:regenerate_activities` |

## Out of scope

- `generate_file` xlsx/pdf/docx (later slice)
- AI/geo optional client gems (later)
- authorize/pundit/eval paths (security pass later)

## Success criteria

1. No `defined?(Barby|RQRCode|Liquid|Loofah|MiniMagick|CodeGenerators::Support)` in touched generators
2. Direct `barby` + `liquid` in Gemfile
3. Specs green; audits 0 defects
