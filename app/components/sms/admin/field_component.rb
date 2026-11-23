# frozen_string_literal: true

module Sms
  module Admin
    class FieldComponent < ApplicationComponent
      attr_reader :form, :field, :value, :label, :type, :options, :help, :attributes

      def initialize(form:, field:, value:, label:, type: :text, options: [], help: nil, errors: {}, attributes: {})
        @form, @field, @value, @label, @type = form, field, value, label, type
        @options, @help, @errors, @attributes = options, help, errors || {}, attributes
      end

      def id = "#{form.object_name}_#{field}"
      def messages
        canonical = field == :scheduled_local ? :scheduled_at : field.to_s.sub(/_json\z/, "").to_sym
        Array(@errors[field]) + Array(@errors[canonical])
      end

      def control_attributes
        { id: id, class: "input-field w-full min-w-0", value: value,
          aria: { invalid: messages.any? ? true : nil,
                  describedby: [help.present? ? "#{id}_help" : nil, messages.any? ? "#{id}_errors" : nil].compact.join(" ").presence } }.merge(attributes)
      end

      def control
        case type
        when :select
          form.select(field, options, { selected: value }, control_attributes.except(:value))
        when :textarea
          form.text_area(field, control_attributes.merge(class: "input-field w-full min-w-0 min-h-48 font-mono text-sm"))
        when :number
          form.number_field(field, control_attributes)
        when :datetime_local
          form.datetime_local_field(field, control_attributes)
        when :tel
          form.telephone_field(field, control_attributes)
        else
          form.text_field(field, control_attributes)
        end
      end
    end
  end
end
