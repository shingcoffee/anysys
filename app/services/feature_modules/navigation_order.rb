# frozen_string_literal: true

module FeatureModules
  # One order for module navigation in both the Modules and Settings areas.
  # Unrecognized modules remain available after the built-in modules.
  module NavigationOrder
    KEYS = %w[authentication payment email sms website captcha ai_assistant].freeze
    POSITION = KEYS.each_with_index.to_h.freeze

    # Sections group modules by what the customer uses them for; the Modules
    # hub, Modules sidebar and Settings sidebar share these headings.
    SECTIONS = {
      "authentication" => :records,
      "website"        => :records,
      "email"          => :communication,
      "sms"            => :communication,
      "payment"        => :communication,
      "captcha"        => :growth,
      "ai_assistant"   => :growth
    }.freeze
    SECTION_ORDER = %i[records communication growth other].freeze

    def self.sort(modules)
      modules.sort_by { |mod| [POSITION.fetch(mod.key, KEYS.size), mod.name.to_s.downcase, mod.key] }
    end

    def self.section_for(key)
      SECTIONS.fetch(key.to_s, :other)
    end

    def self.section_label(section)
      I18n.t("admin_modules.index.sections.#{section}")
    end

    # Ordered [section, items] pairs for items already in navigation order;
    # empty sections are skipped. The block returns each item's module key.
    def self.by_section(items, &module_key)
      grouped = items.group_by { |item| section_for(module_key.call(item)) }
      SECTION_ORDER.filter_map { |section| [section, grouped[section]] if grouped[section] }
    end
  end
end
