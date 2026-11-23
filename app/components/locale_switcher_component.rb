# frozen_string_literal: true

# LocaleSwitcherComponent
#
# A compact globe dropdown that switches the UI language between the
# application's available locales. Each option submits a PATCH to /locale
# (LocalesController), which persists the choice (user preference + cookie)
# and redirects back to the current page.
#
# Languages are listed by their endonym (each language in its own name), which
# is the same regardless of the active locale — so no translation is needed for
# the option labels themselves.
class LocaleSwitcherComponent < ApplicationComponent
  # Endonyms — a language is always shown in its own script.
  DISPLAY_NAMES = {
    en:        "English",
    "zh-CN":   "简体中文"
  }.freeze

  # @param current [Symbol] the locale currently in effect
  # @param align [Symbol] dropdown alignment, :right (default) or :left
  # @param inverted [Boolean] marketing-site chrome on a dark background
  # @param labelled [Boolean] keep the language name visible on small screens
  def initialize(current: I18n.locale, align: :right, inverted: false, labelled: false)
    @current = current.to_sym
    @align = align
    @inverted = inverted
    @labelled = labelled
  end

  attr_reader :current, :align

  def inverted?
    @inverted
  end

  def labelled?
    @labelled
  end

  def trigger_class
    if inverted?
      "inline-flex items-center gap-1.5 px-2 py-1.5 rounded-lg hover:bg-white/10 text-sm text-white/80 transition-base"
    else
      "inline-flex items-center gap-1.5 px-2 py-1.5 rounded-lg hover:bg-surface-active text-sm text-text-secondary transition-base"
    end
  end

  def icon_class
    inverted? ? "w-5 h-5 text-white/70" : "w-5 h-5 text-text-muted"
  end

  def label_class
    display = labelled? ? "inline" : "hidden sm:inline"
    inverted? ? "#{display} font-medium text-white" : "#{display} font-medium text-text-primary"
  end

  def chevron_class
    display = labelled? ? "block" : "hidden sm:block"
    inverted? ? "#{display} w-4 h-4 text-white/70" : "#{display} w-4 h-4 text-text-muted"
  end

  def panel_class
    alignment = panel_alignment_class
    if inverted?
      "hidden absolute #{alignment} mt-2 w-44 rounded-xl border border-white/10 bg-neutral-950 py-2 z-50 shadow-xl"
    else
      "hidden absolute #{alignment} mt-2 w-44 dropdown-panel py-2 z-50"
    end
  end

  def panel_heading_class
    inverted? ? "px-4 py-2 border-b border-white/10 mb-1" : "px-4 py-2 border-b border-border mb-1"
  end

  def panel_heading_label_class
    inverted? ? "text-xs font-medium uppercase tracking-wide text-white/50" : "text-xs font-medium uppercase tracking-wide text-text-muted"
  end

  def option_class(locale)
    current_tone = if inverted?
      current?(locale) ? "text-white font-medium" : "text-white/70"
    else
      current?(locale) ? "text-text-primary font-medium" : "text-text-secondary"
    end
    hover = inverted? ? "hover:bg-white/10" : "hover:bg-surface-hover"
    "flex items-center justify-between gap-3 w-full text-left px-4 py-2.5 text-sm #{hover} transition-base #{current_tone}"
  end

  def check_class
    inverted? ? "w-4 h-4 text-white" : "w-4 h-4 text-accent"
  end

  def locales
    I18n.available_locales
  end

  def display_name(locale)
    DISPLAY_NAMES.fetch(locale.to_sym, locale.to_s)
  end

  def current_display_name
    display_name(current)
  end

  def current?(locale)
    locale.to_sym == current
  end

  def panel_alignment_class
    align == :left ? "left-0" : "right-0"
  end
end
