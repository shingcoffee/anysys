# frozen_string_literal: true

module Admin
  module Entities
    # Consumes EntryForm descriptors only; schema parsing and options belong to
    # the form service. The adapter owns presentation around reusable controls.
    class EntryFieldComponent < ApplicationComponent
      CONTROLS = {
        "text" => FormFields::TextFieldComponent,
        "search" => FormFields::TextFieldComponent,
        "tel" => FormFields::TextFieldComponent,
        "url" => FormFields::TextFieldComponent,
        "email" => FormFields::EmailFieldComponent,
        "textarea" => FormFields::TextareaFieldComponent,
        "number" => FormFields::NumberFieldComponent,
        "date" => FormFields::DateFieldComponent,
        "datetime-local" => FormFields::DateTimeFieldComponent,
        "select" => FormFields::SelectFieldComponent,
        "multi-select" => FormFields::SelectFieldComponent,
        "radio" => FormFields::RadioFieldComponent,
        "checkbox" => FormFields::CheckboxFieldComponent,
        "switch" => FormFields::ToggleFieldComponent
      }.freeze
      CONSTRAINTS = %i[min max step minlength maxlength].freeze
      FULL_WIDTH_TYPES = %w[textarea radio multi-select].freeze

      attr_reader :field, :value, :errors, :quick_add, :id_prefix, :name_prefix

      # +quick_add+ is the FormFields::SelectFieldComponent "+ Add New" config;
      # only single selects use it. +id_prefix+ keeps ids unique when nested
      # quick-add forms share the page; +name_prefix+ does the same for the
      # submitted keys when one form posts several entries.
      def initialize(field:, value:, errors:, quick_add: nil, id_prefix: "entry", name_prefix: "entry[data]")
        @field = field
        @value = value
        @errors = Array(errors)
        @quick_add = quick_add
        @id_prefix = id_prefix
        @name_prefix = name_prefix
      end

      def self.field_id(slug, prefix = "entry") = "#{prefix}_#{slug}"

      def field_id = self.class.field_id(field.slug, id_prefix)
      def help_id = "#{field_id}_help"
      def errors_id = "#{field_id}_errors"
      def radio? = html_type == "radio"
      def boolean? = %w[checkbox switch].include?(html_type)
      def multiple? = html_type == "multi-select"
      def invalid? = errors.any?
      def field_name = "#{name_prefix}[#{field.slug}]#{'[]' if multiple?}"

      def wrapper_classes
        classes = "min-w-0 space-y-1.5"
        classes += " md:col-span-2" if field.full_width || FULL_WIDTH_TYPES.include?(html_type)
        classes
      end

      # Browsers leave an unchecked box and an emptied multi-select out of the
      # submission; a hidden input posts their cleared value instead.
      def cleared_value
        if boolean? then "0"
        elsif multiple? then ""
        end
      end

      def control
        klass = raw_literal? ? FormFields::TextFieldComponent : CONTROLS.fetch(html_type)
        klass.new(**control_options)
      end

      def inline_errors
        messages = errors.dup
        if invalid? && radio? && rejected_choices.any?
          messages << rejected_value_label(value)
        end
        messages
      end

      private

      def html_type = field.html_type.presence || "text"

      def raw_literal?
        field.invalid_literal && %w[number date datetime-local].include?(html_type)
      end

      def described_by
        [(help_id if field.help_text.present?), (errors_id if invalid?)].compact.join(" ").presence
      end

      def control_classes
        classes = if radio? || html_type == "checkbox"
          "size-4 shrink-0 rounded border-border text-accent focus:ring-accent"
        else
          "input-field w-full min-w-0 min-h-11 rounded-lg text-sm sm:min-h-10"
        end
        classes += " !border-danger focus:!border-danger" if invalid?
        classes
      end

      def control_options
        constraints = field.constraints.to_h.symbolize_keys.slice(*CONSTRAINTS)
        constraints = constraints.except(:min, :max, :step) if raw_literal?
        options = constraints.merge(
          field_name: field_name, label: field.label, value: value,
          id: field_id, input_only: true, required: field.required && !boolean?,
          class: control_classes,
          aria: { invalid: invalid? ? "true" : nil, describedby: described_by }
        )

        case html_type
        when "text", "search", "tel", "url"
          options[:input_type] = html_type
        when "number"
          if raw_literal?
            options[:inputmode] = field.constraints.to_h.stringify_keys["step"].to_s == "1" ? "numeric" : "decimal"
          end
        when "select", "multi-select"
          options.merge!(options: select_options, multiple: multiple?, include_blank: !multiple?, quick_add: quick_add)
        when "radio"
          options[:options] = field.options.map { |label, option_value| { "label" => label, "value" => option_value } }
        when "checkbox"
          options[:checked] = [true, 1, "1", "true"].include?(value)
        end
        options
      end

      def rejected_choices
        allowed = field.options.map { |_label, option_value| option_value.to_s }
        Array(value).reject { |item| item.to_s.empty? || allowed.include?(item.to_s) }
      end

      def select_options
        # Error options preserve the attempt; they do not change allowed values.
        field.options + (invalid? ? rejected_choices.map { |item| [rejected_value_label(item), item] } : [])
      end

      def rejected_value_label(item)
        I18n.t("admin_misc.entities.entry_form.errors.rejected_value", value: item)
      end
    end
  end
end
