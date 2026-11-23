# frozen_string_literal: true

module PageBuilder
  class ConfigModalComponent < ApplicationComponent
    include ComponentClasses

    # Optional pinned action bar rendered at the bottom of the dialog (outside the
    # scrolling body). Used by the settings modal for its Save / Cancel controls.
    renders_one :footer

    SIZES = {
      sm:    "max-w-md",
      md:    "max-w-2xl",
      lg:    "max-w-4xl",
      xl:    "max-w-5xl",
      "2xl": "max-w-6xl"
    }.freeze

    ACCENTS = {
      slate:  { soft: "bg-slate-100",  icon: "text-slate-600" },
      indigo: { soft: "bg-indigo-50",  icon: "text-indigo-600" },
      purple: { soft: "bg-purple-50",  icon: "text-purple-600" }
    }.freeze

    def initialize(key:, title:, subtitle: nil, icon: nil, accent: :slate, size: :md, fixed_height: false)
      @key          = key
      @title        = title
      @subtitle     = subtitle
      @icon         = icon&.to_sym
      @accent       = accent.to_sym
      @size         = size.to_sym
      @fixed_height = fixed_height
    end

    private

    attr_reader :key, :title, :subtitle, :icon, :accent, :size

    def max_width
      SIZES.fetch(size, SIZES[:md])
    end

    # Height strategy. Content modals grow to fit their content and cap at 85vh.
    # A `fixed_height` modal (e.g. Settings) instead holds a stable ~700px frame
    # so switching between sections never resizes the dialog — the panes scroll
    # inside it. Still capped at 85vh so short viewports stay usable.
    def height_class
      @fixed_height ? "h-[min(85vh,700px)]" : "max-h-[85vh]"
    end

    # A fixed-height dialog delegates scrolling to its inner panes (so a sidebar
    # can stay put while one pane scrolls); a content dialog scrolls its body.
    def body_class
      @fixed_height ? "flex-1 min-h-0 flex" : "flex-1 min-h-0 overflow-y-auto"
    end

    def accent_classes
      ACCENTS.fetch(accent, ACCENTS[:slate])
    end

    def icon_path
      {
        templates:    "M4 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM14 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 16a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1H5a1 1 0 01-1-1v-3zM14 16a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1h-4a1 1 0 01-1-1v-3z",
        theme:        "M4.098 19.902a3.75 3.75 0 005.304 0l6.401-6.402M6.75 21A3.75 3.75 0 013 17.25V4.125C3 3.504 3.504 3 4.125 3h5.25c.621 0 1.125.504 1.125 1.125V11l-3.75 3.75M6.75 21l3.75-3.75M6.75 21h7.5",
        rules:        "M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4",
        calculations: "M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z",
        settings:     "M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z"
      }[icon]
    end
  end
end
