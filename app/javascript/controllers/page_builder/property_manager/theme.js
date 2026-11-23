/**
 * ThemeMixin provides theme management, preset application, and canvas
 * theme rendering for the property panel.
 * Apply to a class using Object.assign(YourClass.prototype, ThemeMixin)
 */
export const ThemeMixin = {
  // Theme management
  updateTheme(event) {
    const property = event.currentTarget.dataset.themeProperty
    const value = event.currentTarget.dataset.themeValue
    if (!property || !value) return

    this.c.undoRedoManager.saveState()

    this.c.configuration.theme = this.c.configuration.theme || {}
    this.c.configuration.theme[property] = value

    // Update active state on theme selectors
    const container = event.currentTarget.closest("[data-theme-group]")
    if (container) {
      container.querySelectorAll("[data-theme-value]").forEach(el => {
        el.classList.remove("ring-2", "ring-indigo-500", "ring-offset-2")
      })
      event.currentTarget.classList.add("ring-2", "ring-indigo-500", "ring-offset-2")
    }

    this.applyThemeToCanvas()
    this.c.fieldManager.renderFields()
    this.c.saveManager.markDirty()
  },

  applyThemePreset(event) {
    const presetName = event.currentTarget.dataset.preset
    if (!presetName) return

    const presets = {
      modern: {
        primary_color: "indigo", accent_color: "indigo", font_family: "sans",
        border_radius: "lg", input_style: "outline", form_background: "white",
        form_width: "xl", form_shadow: "lg", form_padding: "spacious",
        form_border: "none", field_spacing: "normal", input_size: "md",
        label_style: "default", button_style: "gradient", button_width: "full", button_size: "md"
      },
      minimalist: {
        primary_color: "slate", accent_color: "slate", font_family: "sans",
        border_radius: "sm", input_style: "underline", form_background: "white",
        form_width: "lg", form_shadow: "none", form_padding: "normal",
        form_border: "none", field_spacing: "tight", input_size: "md",
        label_style: "uppercase", button_style: "outline", button_width: "auto", button_size: "md"
      },
      bold: {
        primary_color: "rose", accent_color: "rose", font_family: "sans",
        border_radius: "full", input_style: "filled", form_background: "white",
        form_width: "xl", form_shadow: "md", form_padding: "normal",
        form_border: "none", field_spacing: "normal", input_size: "lg",
        label_style: "bold", button_style: "filled", button_width: "full", button_size: "lg"
      },
      elegant: {
        primary_color: "violet", accent_color: "violet", font_family: "serif",
        border_radius: "md", input_style: "outline", form_background: "warm",
        form_width: "lg", form_shadow: "sm", form_padding: "spacious",
        form_border: "subtle", field_spacing: "relaxed", input_size: "md",
        label_style: "default", button_style: "soft", button_width: "full", button_size: "md"
      },
      playful: {
        primary_color: "emerald", accent_color: "emerald", font_family: "sans",
        border_radius: "full", input_style: "filled", form_background: "white",
        form_width: "xl", form_shadow: "lg", form_padding: "spacious",
        form_border: "none", field_spacing: "normal", input_size: "lg",
        label_style: "default", button_style: "gradient", button_width: "full", button_size: "lg"
      }
    }

    const preset = presets[presetName]
    if (!preset) return

    this.c.undoRedoManager.saveState()
    this.c.configuration.theme = { ...preset }

    // Update all theme selector active states
    Object.entries(preset).forEach(([property, value]) => {
      const group = this.c.element.querySelector(`[data-theme-group="${property}"]`)
      if (group) {
        group.querySelectorAll("[data-theme-value]").forEach(el => {
          el.classList.remove("ring-2", "ring-indigo-500", "ring-offset-2")
          if (el.dataset.themeValue === value) {
            el.classList.add("ring-2", "ring-indigo-500", "ring-offset-2")
          }
        })
      }
    })

    // Update preset button active states
    this.c.element.querySelectorAll("[data-preset]").forEach(el => {
      el.classList.remove("ring-2", "ring-indigo-500")
      if (el.dataset.preset === presetName) {
        el.classList.add("ring-2", "ring-indigo-500")
      }
    })

    this.applyThemeToCanvas()
    this.c.fieldManager.renderFields()
    this.c.saveManager.markDirty()
  },

  applyThemeToCanvas() {
    const theme = this.c.configuration.theme || {}

    // Color mappings for canvas preview
    const colorGradients = {
      indigo: "from-indigo-500 to-purple-600",
      blue: "from-blue-500 to-blue-600",
      emerald: "from-emerald-500 to-emerald-600",
      rose: "from-rose-500 to-rose-600",
      amber: "from-amber-500 to-amber-600",
      violet: "from-violet-500 to-violet-600",
      teal: "from-teal-500 to-teal-600",
      slate: "from-slate-500 to-slate-600"
    }

    const colorBg = {
      indigo: "bg-indigo-600", blue: "bg-blue-600", emerald: "bg-emerald-600",
      rose: "bg-rose-600", amber: "bg-amber-600", violet: "bg-violet-600",
      teal: "bg-teal-600", slate: "bg-slate-600"
    }

    // Update canvas header gradient
    const header = this.c.element.querySelector(".canvas-frame .bg-gradient-to-r")
    if (header) {
      Object.values(colorGradients).forEach(g => {
        g.split(" ").forEach(cls => header.classList.remove(cls))
      })
      const gradient = colorGradients[theme.primary_color] || colorGradients.indigo
      gradient.split(" ").forEach(cls => header.classList.add(cls))
    }

    // Update canvas submit button
    const submitBtn = this.c.element.querySelector(".canvas-frame button[type='submit']")
    if (submitBtn) {
      // Button style
      Object.values(colorBg).forEach(cls => submitBtn.classList.remove(cls))
      submitBtn.classList.remove(
        "bg-transparent", "bg-gradient-to-r", "hover:opacity-90", "border-2",
        ...Object.values(colorGradients).flatMap(g => g.split(" ")),
        "w-auto", "px-8", "w-full",
        "py-2", "py-2.5", "py-3.5", "text-sm", "text-base"
      )

      const btnStyle = theme.button_style || "filled"
      const color = theme.primary_color || "indigo"
      if (btnStyle === "gradient") {
        const grad = colorGradients[color] || colorGradients.indigo
        submitBtn.classList.add("bg-gradient-to-r", ...grad.split(" "), "text-white", "hover:opacity-90")
      } else if (btnStyle === "outline") {
        submitBtn.classList.add("bg-transparent", "border-2", `border-${color}-600`, `text-${color}-600`)
        submitBtn.classList.remove("text-white")
      } else if (btnStyle === "soft") {
        submitBtn.classList.add(`bg-${color}-50`, `text-${color}-600`)
        submitBtn.classList.remove("text-white")
      } else {
        submitBtn.classList.add(colorBg[color] || "bg-indigo-600")
      }

      // Button width
      const btnWidth = theme.button_width || "full"
      submitBtn.classList.add(btnWidth === "auto" ? "w-auto" : "w-full")
      if (btnWidth === "auto") submitBtn.classList.add("px-8")

      // Button size
      const sizeMap = { sm: ["py-2", "text-sm"], md: ["py-2.5", "text-sm"], lg: ["py-3.5", "text-base"] }
      const sizeClasses = sizeMap[theme.button_size] || sizeMap.md
      sizeClasses.forEach(cls => submitBtn.classList.add(cls))
    }

    // Update font on canvas frame
    const canvasFrame = this.c.hasCanvasFrameTarget ? this.c.canvasFrameTarget : null
    if (canvasFrame) {
      canvasFrame.classList.remove("font-sans", "font-serif", "font-mono")
      const fontMap = { sans: "font-sans", serif: "font-serif", mono: "font-mono" }
      canvasFrame.classList.add(fontMap[theme.font_family] || "font-sans")
    }

    // Update form container classes (shadow, padding, border)
    const formContainer = this.c.element.querySelector(".canvas-frame [data-form-container]")
    if (formContainer) {
      // Shadow
      const allShadows = ["shadow-sm", "shadow-md", "shadow-lg", "shadow-xl"]
      formContainer.classList.remove(...allShadows)
      const shadowMap = { sm: "shadow-sm", md: "shadow-md", lg: "shadow-lg", xl: "shadow-xl" }
      if (shadowMap[theme.form_shadow]) formContainer.classList.add(shadowMap[theme.form_shadow])

      // Padding
      const allPaddings = ["p-4", "p-6", "p-8", "p-10"]
      formContainer.classList.remove(...allPaddings)
      const paddingMap = { compact: "p-4", normal: "p-6", spacious: "p-8", generous: "p-10" }
      formContainer.classList.add(paddingMap[theme.form_padding] || "p-6")

      // Border
      const allBorders = ["border", "border-2", "border-gray-100", "border-gray-200", "border-gray-300"]
      formContainer.classList.remove(...allBorders)
      const borderMap = {
        subtle: ["border", "border-gray-100"],
        visible: ["border", "border-gray-200"],
        strong: ["border-2", "border-gray-300"]
      }
      if (borderMap[theme.form_border]) formContainer.classList.add(...borderMap[theme.form_border])

      // Form width
      const allWidths = ["max-w-md", "max-w-lg", "max-w-2xl", "max-w-4xl", "max-w-full"]
      formContainer.classList.remove(...allWidths)
      const widthMap = { sm: "max-w-md", md: "max-w-lg", lg: "max-w-2xl", xl: "max-w-4xl", full: "max-w-full" }
      formContainer.classList.add(widthMap[theme.form_width] || "max-w-4xl")
    }

    // Update field spacing on fields container
    const fieldsContainer = this.c.element.querySelector(".canvas-frame form")
    if (fieldsContainer) {
      const allSpacings = ["space-y-3", "space-y-5", "space-y-6", "space-y-8"]
      fieldsContainer.classList.remove(...allSpacings)
      const spacingMap = { tight: "space-y-3", normal: "space-y-5", relaxed: "space-y-8" }
      fieldsContainer.classList.add(spacingMap[theme.field_spacing] || "space-y-5")
    }
  }
}
