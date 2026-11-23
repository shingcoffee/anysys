# frozen_string_literal: true

module Websites
  module Admin
    # One composer row: drag handle, type badge, prop editors, move/delete.
    class SectionEditorComponent < ApplicationComponent
      PLACEHOLDER_ID = "__SECTION_ID__"
      BUTTON_PAIRS = [%w[primary_label primary_href], %w[secondary_label secondary_href], %w[button_label button_href]].freeze

      FIELD_LABEL_KEYS = Websites::SectionFields::LABEL_KEYS
      OPTION_LABEL_KEYS = Websites::SectionFields::OPTION_LABEL_KEYS

      attr_reader :index, :expanded, :first, :last

      def initialize(section:, index: 0, expanded: false, first: false, last: false,
                     structure_locked: false, site_pages: [], defaults: nil,
                     workspace: false, uploadable: false, step: nil, presentation: nil, theme: nil)
        @presentation = presentation
        @theme = theme
        @step = step
        @section = normalize(section)
        @index = index
        @expanded = expanded
        @first = first
        @last = last
        @structure_locked = structure_locked
        @site_pages = Array(site_pages)
        @defaults = defaults
        @workspace = workspace
        @uploadable = uploadable
      end

      def structure_locked?
        @structure_locked
      end

      def workspace?
        @workspace
      end

      def uploadable?
        @uploadable
      end

      def position_label
        return unless @step

        t("website.admin.pages.edit.section_position", number: @step[:number], total: @step[:total])
      end

      def previous_step
        @step&.dig(:previous)
      end

      def next_step
        @step&.dig(:next)
      end

      def step_nav?
        previous_step.present? || next_step.present?
      end

      def section_id
        @section["id"].presence || PLACEHOLDER_ID
      end

      def section_type
        @section["type"].to_s
      end

      def section_props
        @section["props"]
      end

      def known?
        Websites::SectionKit.known?(section_type)
      end

      def type_label
        return t("website.admin.pages.edit.unknown_section") unless known?

        key = "website.sections.#{section_type}.name"
        I18n.exists?(key) ? t(key) : section_type.humanize
      end

      def preview_text
        %w[headline heading quote kicker eyebrow].each do |key|
          value = section_props[key].to_s
          return value if value.present?
        end
        nil
      end

      def field_schema
        content = Websites::SectionFields.schema_for(section_type).map do |field|
          if marketing_presentation? && field[:key] == "headline"
            field.merge(kind: :textarea)
          else
            field.dup
          end
        end
        marketing_presentation? ? content : content + Websites::SectionFields.style_fields(section_type)
      end

      def marketing_presentation?
        @presentation.is_a?(Websites::HomeSite::Presentation)
      end

      # The platform marketing presentation owns its look, so it has no Design panels.
      def style_targets
        return [] if marketing_presentation? || !known?

        @style_targets ||= Websites::SectionStyles.targets_for(section_type)
      end

      # Section-wide Design: the appearance selects plus background, fonts and scale.
      def section_design
        @section_design ||= design(style_targets.select { |target| target[:kind] == :section },
                                   t("website.admin.pages.style.targets.section"))
      end

      def appearance_fields
        field_schema.select { |field| style_field?(field[:key]) }
      end

      # A text field restyles itself; the first button label carries the shared button styles.
      def field_design(key)
        key = key.to_s
        element = style_targets.select { |target| target[:kind] == :element && target[:array].nil? && target[:field] == key }
        return design(element, field_label(key)) if element.any?
        return unless key == first_button_label

        design(style_targets.select { |target| target[:kind] == :buttons }, t("website.admin.pages.style.targets.buttons"))
      end

      def list_design(key)
        design(style_targets.select { |target| target[:array] == key.to_s }, field_label(key))
      end

      def field_label(key)
        t(FIELD_LABEL_KEYS.fetch(key.to_s))
      end

      def option_label(field_key, option)
        t(OPTION_LABEL_KEYS.fetch(field_key.to_s).fetch(option.to_s))
      end

      def href_field?(key)
        Websites::SectionKit::HREF_KEYS.include?(key.to_s)
      end

      def field_value(field)
        return Websites::SectionKit.style_value(section_props, field[:key]) if style_field?(field[:key])

        section_props[field[:key]].to_s
      end

      def style_field?(key)
        Websites::SectionKit::STYLE_KEYS.include?(key.to_s)
      end

      def field_id(key)
        ["section", section_id, key].join("_")
      end

      def array_items(field)
        raw = section_props[field[:key]]
        list = Array(raw).map { |item| item.respond_to?(:stringify_keys) ? item.stringify_keys : item }
        min = field[:min].to_i
        return Array.new(min) { {} } if list.empty? && min.positive?

        list
      end

      def site_pages
        @site_pages
      end

      def default_props
        hash = @defaults.respond_to?(:stringify_keys) ? @defaults.stringify_keys : section_props
        hash.to_h
      end

      def grouped_fields
        groups = { copy: [], links: [], media: [], options: [], lists: [] }
        content_fields.each { |field| groups[group_for(field)] << field }
        groups.reject { |_key, fields| fields.empty? }
      end

      def group_label(key)
        t("website.admin.pages.form.groups.#{key}")
      end

      def chrome_btn_class
        "inline-flex size-8 items-center justify-center rounded-md text-text-tertiary transition-colors hover:bg-surface-hover hover:text-text-primary disabled:pointer-events-none disabled:opacity-30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent pointer-coarse:size-10"
      end

      # Workspace blocks are consecutive units of one group, separated by quiet
      # dividers instead of headings so the inspector stays label-light.
      def field_sections
        return grouped_fields.map { |group, fields| { group: group, heading: true, units: [{ fields: fields }] } } unless workspace?

        content_units.chunk_while { |a, b| a[:group] == b[:group] }.map { |units| { group: units.first[:group], heading: false, units: units } }
      end

      # Presentation-only composition; the catalog's prop keys remain authoritative.
      def content_units
        pairs = [*BUTTON_PAIRS, %w[attribution role], %w[email phone]]
        schema = content_fields
        keys = schema.pluck(:key)
        schema.each_with_object([]) do |field, list|
          pair = pairs.find { |candidate| candidate.include?(field[:key]) && (candidate - keys).empty? }
          next if pair && field[:key] == pair.last

          fields = pair ? schema.select { |other| pair.include?(other[:key]) } : [field]
          button = pair.first.delete_suffix("_label") if BUTTON_PAIRS.include?(pair)
          list << { fields: fields, button: button, optional: button == "secondary", group: group_for(field) }
        end
      end

      def button_label(button)
        t(button == "button" ? "comp_page_builder.component_palette.button" : "website.admin.pages.form.buttons.#{button}")
      end

      def field_component(field, button: nil)
        if field[:kind] == :array
          return ArrayFieldComponent.new(field: field, items: array_items(field), field_id: field_id(field[:key]),
                                         site_pages: site_pages, uploadable: uploadable?, workspace: workspace?,
                                         design: list_design(field[:key]))
        end

        label_key = if button
          href_field?(field[:key]) ? "website.admin.pages.form.destination" : "website.admin.pages.form.fields.button_label"
        end
        PropFieldComponent.new(field: field, value: field_value(field), field_id: field_id(field[:key]),
                               site_pages: site_pages, uploadable: uploadable?, workspace: workspace?, label_key: label_key,
                               option_label: ->(option) { option_label(field[:key], option) },
                               design: field_design(field[:key]))
      end

      def type_description
        return unless known?

        key = "website.sections.#{section_type}.description"
        t(key) if I18n.exists?(key)
      end

      def row_classes
        return "min-w-0" if workspace?

        classes = ["rounded-xl border bg-surface shadow-sm"]
        classes << (known? ? "border-border-subtle" : "border-warning/30 bg-warning-subtle/40")
        classes.join(" ")
      end

      private

      def content_fields
        field_schema.reject { |field| style_field?(field[:key]) }
      end

      def first_button_label
        @first_button_label ||= field_schema.pluck(:key).find { |key| Websites::SectionStyles::BUTTON_LABELS.include?(key) }
      end

      def design(targets, label)
        return if targets.empty?

        StylePanelComponent.new(section_id: section_id, targets: targets, label: label,
                                styles: section_props[Websites::SectionStyles::PROP], theme: @theme)
      end

      def normalize(section)
        hash = section.respond_to?(:to_h) ? section.to_h : {}
        hash = hash.stringify_keys if hash.respond_to?(:stringify_keys)
        props = hash["props"] || hash[:props] || {}
        props = props.stringify_keys if props.respond_to?(:stringify_keys)
        {
          "id" => hash["id"] || hash[:id],
          "type" => hash["type"] || hash[:type],
          "props" => props
        }
      end

      def group_for(field)
        return :lists if field[:kind] == :array

        key = field[:key].to_s
        return :links if href_field?(key) || button_label_field?(key)
        return :media if %w[image_url visual_url].include?(key)
        return :options if field[:kind] == :select

        :copy
      end

      def button_label_field?(key)
        BUTTON_PAIRS.any? do |label, href|
          label == key && field_schema.any? { |field| field[:key] == href }
        end
      end
    end
  end
end
