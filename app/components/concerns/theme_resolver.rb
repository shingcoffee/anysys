# frozen_string_literal: true

require_relative "theme_resolver/palette_resolution"
require_relative "theme_resolver/layout_resolution"
require_relative "theme_resolver/element_resolution"
require_relative "theme_resolver/preset_resolution"

module ThemeResolver
  extend ActiveSupport::Concern

  COLOR_PALETTES = {
    "indigo" => {
      bg: "bg-indigo-600",
      hover: "hover:bg-indigo-700",
      ring: "focus:ring-indigo-500",
      border: "focus:border-indigo-500",
      text: "text-indigo-600",
      light_bg: "bg-indigo-50",
      gradient_from: "from-indigo-600",
      gradient_to: "to-indigo-500",
      soft_bg: "bg-indigo-50",
      soft_hover: "hover:bg-indigo-100",
      outline_hover: "hover:bg-indigo-50",
      ring_color: "ring-indigo-500",
      border_accent: "border-indigo-200",
      border_accent_strong: "border-indigo-500",
      checked_track: "peer-checked:bg-indigo-600"
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
      border_accent: "border-blue-200",
      border_accent_strong: "border-blue-500",
      checked_track: "peer-checked:bg-blue-600"
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
      border_accent: "border-emerald-200",
      border_accent_strong: "border-emerald-500",
      checked_track: "peer-checked:bg-emerald-600"
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
      border_accent: "border-rose-200",
      border_accent_strong: "border-rose-500",
      checked_track: "peer-checked:bg-rose-600"
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
      border_accent: "border-amber-200",
      border_accent_strong: "border-amber-500",
      checked_track: "peer-checked:bg-amber-600"
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
      border_accent: "border-violet-200",
      border_accent_strong: "border-violet-500",
      checked_track: "peer-checked:bg-violet-600"
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
      border_accent: "border-teal-200",
      border_accent_strong: "border-teal-500",
      checked_track: "peer-checked:bg-teal-600"
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
      border_accent: "border-slate-200",
      border_accent_strong: "border-slate-500",
      checked_track: "peer-checked:bg-slate-700"
    }
  }.freeze

  ELEMENT_NEUTRALS = {
    muted_text:    "text-gray-500",
    faint_text:    "text-gray-400",
    body_text:     "text-gray-600",
    strong_text:   "text-gray-900",
    subtle_border: "border-gray-100",
    soft_border:   "border-gray-200",
    surface:       "bg-white",
    surface_muted: "bg-gray-50",
    track:         "bg-gray-100"
  }.freeze

  RADIUS_MAP = {
    "none" => "rounded-none",
    "sm"   => "rounded",
    "md"   => "rounded-md",
    "lg"   => "rounded-lg",
    "full" => "rounded-full"
  }.freeze

  # Large surfaces (form card) clamp "full" to a soft radius — rounded-full on
  # a tall container renders as an ellipse.
  CONTAINER_RADIUS_MAP = RADIUS_MAP.merge("full" => "rounded-3xl").freeze

  FONT_MAP = {
    "sans"  => "font-sans",
    "serif" => "font-serif",
    "mono"  => "font-mono"
  }.freeze

  INPUT_STYLES = {
    "outline"   => "border border-gray-300 bg-white hover:border-gray-400 hover:shadow-sm transition-all duration-150",
    "filled"    => "border-0 bg-gray-100 hover:bg-gray-200/70 transition-colors duration-150",
    "underline" => "border-0 border-b-2 border-gray-300 bg-transparent rounded-none hover:border-gray-500 transition-colors duration-150"
  }.freeze

  FORM_BG_MAP = {
    "white" => "bg-white",
    "gray"  => "bg-gray-50",
    "warm"  => "bg-amber-50/60"
  }.freeze

  ACCENT_PALETTES = {
    "indigo"  => { text: "text-indigo-600",  bg: "bg-indigo-100",  border: "border-indigo-400",  ring: "ring-indigo-500"  },
    "blue"    => { text: "text-blue-600",    bg: "bg-blue-100",    border: "border-blue-400",    ring: "ring-blue-500"    },
    "emerald" => { text: "text-emerald-600", bg: "bg-emerald-100", border: "border-emerald-400", ring: "ring-emerald-500" },
    "rose"    => { text: "text-rose-600",    bg: "bg-rose-100",    border: "border-rose-400",    ring: "ring-rose-500"    },
    "amber"   => { text: "text-amber-600",   bg: "bg-amber-100",   border: "border-amber-400",   ring: "ring-amber-500"   },
    "violet"  => { text: "text-violet-600",  bg: "bg-violet-100",  border: "border-violet-400",  ring: "ring-violet-500"  },
    "teal"    => { text: "text-teal-600",    bg: "bg-teal-100",    border: "border-teal-400",    ring: "ring-teal-500"    },
    "slate"   => { text: "text-slate-600",   bg: "bg-slate-100",   border: "border-slate-400",   ring: "ring-slate-500"   }
  }.freeze

  FORM_WIDTH_MAP = {
    "sm"   => "max-w-md",
    "md"   => "max-w-lg",
    "lg"   => "max-w-2xl",
    "xl"   => "max-w-4xl",
    "full" => "max-w-full"
  }.freeze

  FORM_SHADOW_MAP = {
    "none" => "",
    "sm"   => "shadow-sm",
    "md"   => "shadow-md",
    "lg"   => "shadow-lg",
    "xl"   => "shadow-xl"
  }.freeze

  FORM_PADDING_MAP = {
    "compact"  => "p-4",
    "normal"   => "p-6",
    "spacious" => "p-8",
    "generous" => "p-10"
  }.freeze

  FORM_BORDER_MAP = {
    "none"    => "",
    "subtle"  => "border border-gray-100",
    "visible" => "border border-gray-200",
    "strong"  => "border-2 border-gray-300"
  }.freeze

  FIELD_SPACING_MAP = {
    "tight"   => "space-y-3",
    "normal"  => "space-y-5",
    "relaxed" => "space-y-8"
  }.freeze

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

  HEADING_TOP_MARGIN_MAP = {
    "tight"   => "mt-2",
    "normal"  => "mt-3",
    "relaxed" => "mt-4"
  }.freeze

  INPUT_SIZE_MAP = {
    "sm" => "px-2.5 py-1.5 text-sm",
    "md" => "px-3 py-2 text-sm",
    "lg" => "px-4 py-3 text-base"
  }.freeze

  LABEL_STYLE_MAP = {
    "default"   => "block text-sm font-medium text-gray-700 mb-1 transition-colors",
    "bold"      => "block text-sm font-bold text-gray-900 mb-1",
    "uppercase" => "block text-xs font-semibold text-gray-500 uppercase tracking-widest mb-2",
    "floating"  => "block text-xs font-medium text-gray-500 mb-0.5"
  }.freeze

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

  BUTTON_WIDTH_MAP = {
    "auto" => "w-auto px-8",
    "full" => "w-full"
  }.freeze

  BUTTON_SIZE_MAP = {
    "sm" => "py-2 text-sm",
    "md" => "py-2.5 text-sm",
    "lg" => "py-3.5 text-base"
  }.freeze

  THEME_PRESETS = {
    "modern" => {
      "primary_color" => "indigo", "accent_color" => "indigo", "font_family" => "sans",
      "border_radius" => "lg", "input_style" => "outline", "form_background" => "white",
      "form_width" => "xl", "form_shadow" => "lg", "form_padding" => "spacious",
      "form_border" => "none", "field_spacing" => "normal", "input_size" => "md",
      "label_style" => "default", "button_style" => "gradient", "button_width" => "full", "button_size" => "md"
    },
    "minimalist" => {
      "primary_color" => "slate", "accent_color" => "slate", "font_family" => "sans",
      "border_radius" => "sm", "input_style" => "underline", "form_background" => "white",
      "form_width" => "lg", "form_shadow" => "none", "form_padding" => "normal",
      "form_border" => "none", "field_spacing" => "tight", "input_size" => "md",
      "label_style" => "uppercase", "button_style" => "outline", "button_width" => "auto", "button_size" => "md"
    },
    "bold" => {
      "primary_color" => "rose", "accent_color" => "rose", "font_family" => "sans",
      "border_radius" => "full", "input_style" => "filled", "form_background" => "white",
      "form_width" => "xl", "form_shadow" => "md", "form_padding" => "normal",
      "form_border" => "none", "field_spacing" => "normal", "input_size" => "lg",
      "label_style" => "bold", "button_style" => "filled", "button_width" => "full", "button_size" => "lg"
    },
    "elegant" => {
      "primary_color" => "violet", "accent_color" => "violet", "font_family" => "serif",
      "border_radius" => "md", "input_style" => "outline", "form_background" => "warm",
      "form_width" => "lg", "form_shadow" => "sm", "form_padding" => "spacious",
      "form_border" => "subtle", "field_spacing" => "relaxed", "input_size" => "md",
      "label_style" => "default", "button_style" => "soft", "button_width" => "full", "button_size" => "md"
    },
    "playful" => {
      "primary_color" => "emerald", "accent_color" => "emerald", "font_family" => "sans",
      "border_radius" => "full", "input_style" => "filled", "form_background" => "white",
      "form_width" => "xl", "form_shadow" => "lg", "form_padding" => "spacious",
      "form_border" => "none", "field_spacing" => "normal", "input_size" => "lg",
      "label_style" => "default", "button_style" => "gradient", "button_width" => "full", "button_size" => "lg"
    },
    "showcase" => {
      "primary_color" => "violet", "accent_color" => "violet", "font_family" => "sans",
      "border_radius" => "lg", "input_style" => "outline", "form_background" => "white",
      "form_width" => "full", "form_shadow" => "xl", "form_padding" => "generous",
      "form_border" => "subtle", "field_spacing" => "relaxed", "input_size" => "lg",
      "label_style" => "uppercase", "button_style" => "gradient", "button_width" => "full", "button_size" => "lg"
    }
  }.freeze

  THEME_DEFAULTS = {
    "primary_color"   => "indigo",
    "accent_color"    => "indigo",
    "font_family"     => "sans",
    "border_radius"   => "lg",
    "input_style"     => "outline",
    "form_background" => "white",
    "form_width"      => "xl",
    "form_shadow"     => "none",
    "form_padding"    => "normal",
    "form_border"     => "none",
    "field_spacing"   => "normal",
    "input_size"      => "md",
    "label_style"     => "default",
    "button_style"    => "filled",
    "button_width"    => "full",
    "button_size"     => "md"
  }.freeze

  PAGE_CHROME_BG_MAP = {
    "modern"     => "bg-gradient-to-br from-slate-50 to-indigo-50",
    "minimalist" => "bg-white",
    "bold"       => "bg-rose-50",
    "elegant"    => "bg-amber-50",
    "playful"    => "bg-emerald-50",
    "showcase"   => "bg-gradient-to-br from-violet-950 via-violet-900 to-indigo-900"
  }.freeze

  # Fallback wash for customized themes (no exact preset match), keyed by primary_color
  PAGE_CHROME_BG_BY_HUE = {
    "indigo"  => "bg-gradient-to-br from-slate-50 to-indigo-50",
    "blue"    => "bg-gradient-to-br from-slate-50 to-blue-50",
    "emerald" => "bg-emerald-50/60",
    "rose"    => "bg-rose-50/60",
    "amber"   => "bg-amber-50/60",
    "violet"  => "bg-gradient-to-br from-slate-50 to-violet-50",
    "teal"    => "bg-teal-50/60",
    "slate"   => "bg-slate-50"
  }.freeze

  PAGE_CHROME_HEADER_MAP = {
    "modern"     => "text-gray-900",
    "minimalist" => "text-gray-900",
    "bold"       => "text-rose-700",
    "elegant"    => "text-violet-900",
    "playful"    => "text-emerald-800",
    "showcase"   => "text-white"
  }.freeze

  PAGE_CHROME_DESC_MAP = {
    "modern"     => "text-gray-500",
    "minimalist" => "text-gray-400",
    "bold"       => "text-rose-400",
    "elegant"    => "text-violet-400",
    "playful"    => "text-emerald-600",
    "showcase"   => "text-violet-200"
  }.freeze

  PAGE_CHROME_CARD_MAP = {
    "modern"     => "rounded-xl overflow-hidden",
    "minimalist" => "",
    "bold"       => "rounded-2xl overflow-hidden border-t-4 border-rose-500",
    "elegant"    => "rounded-lg overflow-hidden",
    "playful"    => "rounded-3xl overflow-hidden",
    "showcase"   => "rounded-2xl overflow-hidden shadow-2xl"
  }.freeze

  included do
    include ThemeResolver::PaletteResolution
    include ThemeResolver::LayoutResolution
    include ThemeResolver::ElementResolution
    include ThemeResolver::PresetResolution
  end

  private

  def resolve_theme(theme)
    THEME_DEFAULTS.merge(theme || {})
  end
end
