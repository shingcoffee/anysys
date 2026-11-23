import { escapeHtml } from "utils"
import { FIELD_INPUT_CLASSES, resolveControlLabels } from "controllers/property_editor/controls/shared"

const LOCALES = [
  { key: "en", labelKey: "localeEnLabel" },
  { key: "zh-CN", labelKey: "localeZhCnLabel" }
]

function localeHash(value) {
  if (value && typeof value === "object" && !Array.isArray(value)) return value
  if (typeof value === "string" && value !== "") return { en: value }
  return {}
}

export function buildLocalizedTextField(field, value, context = {}) {
  const labels = resolveControlLabels(context.labels)
  const hash = localeHash(value)
  const required = field.required === true
  const tabs = LOCALES.map((locale, index) => {
    const active = index === 0
    const activeClasses = active
      ? "bg-white text-slate-900 shadow-sm ring-1 ring-black/5"
      : "text-slate-500 hover:text-slate-700 hover:bg-white/50"
    return `<button type="button" role="tab" data-locale-tab="${locale.key}"
                aria-selected="${active ? "true" : "false"}"
                data-action="click->property-editor#switchLocalizedLocale"
                class="flex-1 py-1 px-3 text-[11px] font-medium rounded-md transition-all duration-150 ${activeClasses}">
        ${escapeHtml(labels[locale.labelKey])}
      </button>`
  }).join("")
  const panels = LOCALES.map((locale, index) => {
    const text = hash[locale.key] ?? hash[locale.key.replace("-", "_")] ?? ""
    const requiredAttr = locale.key === "en" && required ? " required" : ""
    return `<div data-locale-panel="${locale.key}" class="${index === 0 ? "" : "hidden "}flex flex-col gap-1">
        <input type="text" data-locale-input data-locale="${locale.key}"
               value="${escapeHtml(String(text))}"${requiredAttr}
               class="${FIELD_INPUT_CLASSES}">
      </div>`
  }).join("")
  return `<div data-localized-text class="flex flex-col gap-1.5">
      <div role="tablist" class="flex gap-1 p-1 bg-slate-100 rounded-lg">${tabs}</div>
      ${panels}
    </div>`
}

export function collectLocalizedText(editor) {
  const hash = {}
  editor.querySelectorAll("[data-locale-input]").forEach(input => {
    const locale = input.dataset.locale
    const text = input.value?.trim()
    if (locale && text) hash[locale] = text
  })
  return hash
}
