import { escapeHtml } from "utils"

/**
 * Flag control — shadcn switch pattern (peer pill) over a real checkbox so
 * collectStepConfig keeps reading a boolean.
 */
export function buildToggleField(field, value) {
  const key = field.name || field.key
  const checked = value === true || value === "true"
  return `<label class="inline-flex items-center cursor-pointer">
    <input type="checkbox"
      data-config-input="${escapeHtml(key)}"
      data-action="change->property-editor#handleConfigFieldChange"
      ${checked ? `checked="checked"` : ""}
      class="sr-only peer">
    <span class="relative h-5 w-9 rounded-full bg-slate-200 transition-colors peer-checked:bg-indigo-600 peer-focus-visible:ring-2 peer-focus-visible:ring-indigo-500/30 after:absolute after:top-0.5 after:left-0.5 after:h-4 after:w-4 after:rounded-full after:bg-white after:transition-transform peer-checked:after:translate-x-4"></span>
  </label>`
}
