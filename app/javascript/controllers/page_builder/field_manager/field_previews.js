/**
 * FieldPreviewsMixin provides field preview HTML generation methods.
 * Apply to a class using Object.assign(YourClass.prototype, FieldPreviewsMixin)
 */
export const FieldPreviewsMixin = {
  // Shared "Option {n}" fallback label (see page_builder_controller.js's
  // `newOptionLabelFormat` Value — same format already used by form_builder.js
  // when a user adds a blank option).
  _defaultOptionLabel(n) {
    return this.c.newOptionLabelFormatValue.replace("{number}", n)
  },

  // Color-coded icon backgrounds based on HTML type category
  _fieldIconStyle(field) {
    const ht = field.html_type || ""
    if (["email", "tel", "url"].includes(ht))                         return { bg: "bg-blue-100", text: "text-blue-600" }
    if (["select", "multi-select", "radio", "checkbox", "switch"].includes(ht)) return { bg: "bg-purple-100", text: "text-purple-600" }
    if (["number", "currency", "range", "rating"].includes(ht))       return { bg: "bg-amber-100", text: "text-amber-600" }
    if (["date", "time", "datetime-local", "month", "week"].includes(ht)) return { bg: "bg-green-100", text: "text-green-600" }
    if (["file", "image", "color"].includes(ht))                      return { bg: "bg-pink-100", text: "text-pink-600" }
    if (["textarea", "rich-text", "signature"].includes(ht))          return { bg: "bg-teal-100", text: "text-teal-600" }
    return { bg: "bg-gray-100", text: "text-gray-500" }
  },

  // Maps theme config values to Tailwind utility classes
  _themeClasses(theme) {
    const radiusMap = { none: "rounded-none", sm: "rounded-sm", md: "rounded-md", lg: "rounded-lg", full: "rounded-full" }
    const sizeMap = { sm: "py-1 px-2 text-xs", md: "py-1.5 px-3 text-sm", lg: "py-2 px-4 text-base" }
    const styleMap = {
      outline: "border border-gray-300 bg-white",
      filled: "border border-transparent bg-gray-100",
      underline: "border-b border-gray-300 bg-transparent rounded-none"
    }
    return {
      radius: radiusMap[theme.border_radius] || "rounded-lg",
      size: sizeMap[theme.input_size] || "py-1.5 px-3 text-sm",
      style: styleMap[theme.input_style] || "border border-gray-300 bg-white",
      primaryColor: theme.primary_color || "indigo"
    }
  },

  // Returns the themed accent color class for active elements
  _accentBg(theme) {
    const color = (theme && theme.primary_color) || "indigo"
    const map = {
      indigo: "bg-indigo-500", blue: "bg-blue-500", emerald: "bg-emerald-500",
      rose: "bg-rose-500", amber: "bg-amber-500", violet: "bg-violet-500",
      teal: "bg-teal-500", slate: "bg-slate-500"
    }
    return map[color] || "bg-indigo-500"
  },

  _accentBorder(theme) {
    const color = (theme && theme.primary_color) || "indigo"
    const map = {
      indigo: "border-indigo-500", blue: "border-blue-500", emerald: "border-emerald-500",
      rose: "border-rose-500", amber: "border-amber-500", violet: "border-violet-500",
      teal: "border-teal-500", slate: "border-slate-500"
    }
    return map[color] || "border-indigo-500"
  },

  _accentText(theme) {
    const color = (theme && theme.primary_color) || "indigo"
    const map = {
      indigo: "text-indigo-600", blue: "text-blue-600", emerald: "text-emerald-600",
      rose: "text-rose-600", amber: "text-amber-600", violet: "text-violet-600",
      teal: "text-teal-600", slate: "text-slate-600"
    }
    return map[color] || "text-indigo-600"
  },

  _accentBgLight(theme) {
    const color = (theme && theme.primary_color) || "indigo"
    const map = {
      indigo: "bg-indigo-50", blue: "bg-blue-50", emerald: "bg-emerald-50",
      rose: "bg-rose-50", amber: "bg-amber-50", violet: "bg-violet-50",
      teal: "bg-teal-50", slate: "bg-slate-50"
    }
    return map[color] || "bg-indigo-50"
  },

  _accentRing(theme) {
    const color = (theme && theme.primary_color) || "indigo"
    const map = {
      indigo: "ring-indigo-200", blue: "ring-blue-200", emerald: "ring-emerald-200",
      rose: "ring-rose-200", amber: "ring-amber-200", violet: "ring-violet-200",
      teal: "ring-teal-200", slate: "ring-slate-200"
    }
    return map[color] || "ring-indigo-200"
  },

  getFieldPreviewHtml(field, theme) {
    if (field.property_type === "layout") return ""

    const t = this._themeClasses(theme || {})
    const placeholder = this.escapeHtml(field.placeholder || this.c.enterFieldPlaceholderFormatValue.replace("{label}", (field.label || "value").toLowerCase()))
    const htmlType = field.html_type || field.field_type || ""

    // HTML-type-specific WYSIWYG previews — covers all 27 html types
    switch (htmlType) {
      // ── Text family ──
      case "text":
      case "search":
        return this._previewInput(field, theme, placeholder, htmlType === "search"
          ? '<svg class="w-3 h-3 text-gray-400 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" /></svg>'
          : "")

      case "password":
        return `<div class="w-full ${t.size} ${t.style} ${t.radius} flex items-center justify-between pointer-events-none">
          <span class="text-gray-400 tracking-widest">&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;</span>
          <svg class="w-3 h-3 text-gray-400 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" /><path stroke-linecap="round" stroke-linejoin="round" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" /></svg>
        </div>`

      case "hidden":
        return `<div class="w-full px-2 py-1 text-[11px] border border-dashed border-gray-200 rounded-lg bg-gray-50/50 text-gray-400 italic pointer-events-none">${this.c.hiddenFieldPreviewLabelValue}</div>`

      case "textarea":
        return `<div class="w-full ${t.size} ${t.style} ${t.radius} pointer-events-none min-h-[2.5rem]">
          <span class="text-gray-400">${placeholder}</span>
        </div>`

      case "rich-text":
        return `<div class="w-full ${t.style} ${t.radius} overflow-hidden pointer-events-none">
          <div class="flex items-center gap-0.5 px-1.5 py-0.5 border-b border-gray-200 bg-gray-100/80">
            <span class="text-[10px] font-bold text-gray-500 px-0.5">B</span>
            <span class="text-[10px] italic text-gray-500 px-0.5">I</span>
            <span class="text-[10px] underline text-gray-500 px-0.5">U</span>
            <span class="text-gray-300 mx-0.5">|</span>
            <svg class="w-2.5 h-2.5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h7" /></svg>
          </div>
          <div class="px-2 py-1 min-h-[1.5rem]"><span class="text-xs text-gray-400">${placeholder}</span></div>
        </div>`

      // ── Contact family ──
      case "email":
        return this._previewInput(field, theme, field.placeholder || "you@example.com",
          '<svg class="w-3 h-3 text-gray-400 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" /></svg>')

      case "tel":
        return this._previewInput(field, theme, field.placeholder || "+1 (555) 000-0000",
          '<svg class="w-3 h-3 text-gray-400 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" /></svg>')

      case "url":
        return this._previewInput(field, theme, field.placeholder || "https://example.com",
          '<svg class="w-3 h-3 text-gray-400 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" /></svg>')

      // ── Selection family ──
      case "select":
        return `<div class="w-full ${t.size} ${t.style} ${t.radius} flex items-center justify-between pointer-events-none">
          <span class="text-gray-400">${field.placeholder || this.c.selectFieldPlaceholderFormatValue.replace("{label}", (field.label || "option").toLowerCase())}</span>
          <svg class="w-3.5 h-3.5 text-gray-400 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" /></svg>
        </div>`

      case "multi-select": {
        const accentBgLight = this._accentBgLight(theme)
        const accentText = this._accentText(theme)
        const accentRing = this._accentRing(theme)
        return `<div class="w-full ${t.size} ${t.style} ${t.radius} flex items-center justify-between pointer-events-none">
          <div class="flex items-center gap-1">
            <span class="inline-flex items-center px-1.5 py-0.5 rounded ${accentBgLight} text-[10px] ${accentText} ring-1 ring-inset ${accentRing}">${this.escapeHtml(this._defaultOptionLabel(1))}</span>
            <span class="inline-flex items-center px-1.5 py-0.5 rounded ${accentBgLight} text-[10px] ${accentText} ring-1 ring-inset ${accentRing}">${this.escapeHtml(this._defaultOptionLabel(2))}</span>
          </div>
          <svg class="w-3.5 h-3.5 text-gray-400 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" /></svg>
        </div>`
      }

      case "radio": {
        const accentBdr = this._accentBorder(theme)
        const accentBg = this._accentBg(theme)
        const options = (field.options && field.options.length > 0) ? field.options : [{ label: this._defaultOptionLabel(1) }, { label: this._defaultOptionLabel(2) }]
        const radioItems = options.map((opt, i) => {
          const label = this.escapeHtml(opt.label || opt.value || this._defaultOptionLabel(i + 1))
          if (i === 0) {
            return `<label class="flex items-center gap-1.5"><div class="w-3.5 h-3.5 border-2 ${accentBdr} rounded-full flex items-center justify-center"><div class="w-1.5 h-1.5 ${accentBg} rounded-full"></div></div><span class="text-xs text-gray-600">${label}</span></label>`
          }
          return `<label class="flex items-center gap-1.5"><div class="w-3.5 h-3.5 border-2 border-gray-300 rounded-full"></div><span class="text-xs text-gray-500">${label}</span></label>`
        }).join("")
        return `<div class="flex flex-col gap-1 pointer-events-none">${radioItems}</div>`
      }

      case "checkbox": {
        const accentBdr = this._accentBorder(theme)
        const accentBg = this._accentBg(theme)
        const options = (field.options && field.options.length > 0) ? field.options : [{ label: this._defaultOptionLabel(1) }, { label: this._defaultOptionLabel(2) }]
        const checkItems = options.map((opt, i) => {
          const label = this.escapeHtml(opt.label || opt.value || this._defaultOptionLabel(i + 1))
          if (i === 0) {
            return `<label class="flex items-center gap-1.5"><div class="w-3.5 h-3.5 border-2 ${accentBdr} rounded ${accentBg} flex items-center justify-center"><svg class="w-2.5 h-2.5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" /></svg></div><span class="text-xs text-gray-600">${label}</span></label>`
          }
          return `<label class="flex items-center gap-1.5"><div class="w-3.5 h-3.5 border-2 border-gray-300 rounded bg-white"></div><span class="text-xs text-gray-500">${label}</span></label>`
        }).join("")
        return `<div class="flex flex-col gap-1 pointer-events-none">${checkItems}</div>`
      }

      case "switch": {
        const accentBg = this._accentBg(theme)
        return `<label class="flex items-center gap-2 pointer-events-none">
          <div class="w-8 h-[18px] ${accentBg} rounded-full relative flex-shrink-0">
            <div class="w-[14px] h-[14px] bg-white rounded-full absolute right-0.5 top-0.5 shadow-sm"></div>
          </div>
          <span class="text-xs text-gray-600">${field.placeholder || this.c.switchEnabledPreviewLabelValue}</span>
        </label>`
      }

      // ── Numeric family ──
      case "number":
        return `<div class="w-full ${t.size} ${t.style} ${t.radius} flex items-center justify-between pointer-events-none">
          <span class="text-gray-400">${field.placeholder || "0"}</span>
          <div class="flex flex-col -my-0.5">
            <svg class="w-2.5 h-2.5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M5 15l7-7 7 7" /></svg>
            <svg class="w-2.5 h-2.5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" /></svg>
          </div>
        </div>`

      case "currency":
        return `<div class="w-full ${t.size} ${t.style} ${t.radius} flex items-center gap-1 pointer-events-none">
          <span class="text-gray-500 font-medium">${field.currency_symbol || "$"}</span>
          <span class="text-gray-400 flex-1">${field.placeholder || "0.00"}</span>
        </div>`

      case "range": {
        const accentBg = this._accentBg(theme)
        const accentBdr = this._accentBorder(theme)
        return `<div class="w-full pointer-events-none">
          <div class="w-full h-1.5 bg-gray-200 rounded-full relative">
            <div class="h-1.5 ${accentBg} rounded-full" style="width: 50%"></div>
            <div class="w-3.5 h-3.5 bg-white border-2 ${accentBdr} rounded-full absolute top-1/2 -translate-y-1/2 shadow-sm" style="left: calc(50% - 7px)"></div>
          </div>
          <div class="flex justify-between text-[10px] text-gray-400 mt-0.5"><span>${field.min_value || "0"}</span><span>${field.max_value || "100"}</span></div>
        </div>`
      }

      case "rating": {
        const maxRating = parseInt(field.max_rating) || 5
        const stars = Array.from({ length: maxRating }, (_, i) =>
          `<svg class="w-3.5 h-3.5 ${i < 3 ? "text-amber-400" : "text-gray-300"}" fill="currentColor" viewBox="0 0 20 20"><path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" /></svg>`
        ).join("")
        return `<div class="flex items-center gap-0.5 pointer-events-none">${stars}</div>`
      }

      // ── Date & Time family ──
      case "date":
        return this._previewInput(field, theme, field.placeholder || "yyyy-mm-dd",
          '<svg class="w-3 h-3 text-gray-400 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" /></svg>')

      case "time":
        return this._previewInput(field, theme, field.placeholder || "HH:MM",
          '<svg class="w-3 h-3 text-gray-400 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>')

      case "datetime-local":
        return this._previewInput(field, theme, field.placeholder || "yyyy-mm-dd HH:MM",
          '<svg class="w-3 h-3 text-gray-400 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" /></svg>')

      case "month":
        return this._previewInput(field, theme, field.placeholder || "yyyy-MM",
          '<svg class="w-3 h-3 text-gray-400 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" /></svg>')

      case "week":
        return this._previewInput(field, theme, field.placeholder || "yyyy-W##",
          '<svg class="w-3 h-3 text-gray-400 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" /></svg>')

      // ── Media & File family ──
      case "file":
        return `<div class="w-full px-3 py-1.5 border-2 border-dashed border-gray-300 ${t.radius} bg-gray-50/50 flex items-center justify-center gap-1.5 pointer-events-none">
          <svg class="w-3.5 h-3.5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" /></svg>
          <span class="text-[11px] text-gray-400">${this.escapeHtml(this.c.dropFileUploadLabelValue)}</span>
        </div>`

      case "image":
        return `<div class="w-full px-3 py-2 border-2 border-dashed border-gray-300 ${t.radius} bg-gray-50/50 flex flex-col items-center justify-center gap-1 pointer-events-none">
          <svg class="w-5 h-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909M3.75 21h16.5A2.25 2.25 0 0022.5 18.75V5.25A2.25 2.25 0 0020.25 3H3.75A2.25 2.25 0 001.5 5.25v13.5A2.25 2.25 0 003.75 21z" /></svg>
          <span class="text-[11px] text-gray-400">${this.escapeHtml(this.c.clickUploadImageLabelValue)}</span>
        </div>`

      case "color": {
        const accentBg = this._accentBg(theme)
        return `<div class="flex items-center gap-2 pointer-events-none">
          <div class="w-6 h-6 ${t.radius} border border-gray-300 ${accentBg} shadow-inner"></div>
          <span class="text-xs text-gray-500 font-mono">#6366f1</span>
        </div>`
      }

      case "signature":
        return `<div class="w-full px-3 py-2 border-2 border-dashed border-gray-300 ${t.radius} bg-gray-50/50 flex items-center justify-center gap-1.5 pointer-events-none min-h-[2.5rem]">
          <svg class="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L6.832 19.82a4.5 4.5 0 01-1.897 1.13l-2.685.8.8-2.685a4.5 4.5 0 011.13-1.897L16.863 4.487zm0 0L19.5 7.125" /></svg>
          <span class="text-[11px] text-gray-400">${this.escapeHtml(this.c.signHerePreviewLabelValue)}</span>
        </div>`

      default:
        // Fallback: generic text input
        return this._previewInput(field, theme, placeholder)
    }
  },

  // Helper: themed input preview with optional leading icon
  _previewInput(field, theme, placeholder, leadingIcon = "") {
    const t = this._themeClasses(theme || {})
    const escaped = this.escapeHtml(placeholder || "")
    const iconHtml = leadingIcon ? `<div class="flex-shrink-0 text-gray-400 mr-2">${leadingIcon}</div>` : ""
    return `<div class="flex items-center ${t.style} ${t.radius} ${t.size} text-gray-400 w-full pointer-events-none">
      ${iconHtml}<span class="truncate">${escaped}</span>
    </div>`
  }
}
