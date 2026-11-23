# frozen_string_literal: true

require "reform/form"

module Websites
  module Contracts
    class Section < Reform::Form
      Input = Struct.new(:id, :type, :props)

      property :id
      property :type
      property :props

      validate :type_is_known
      validate :props_are_well_formed
      validate :hrefs_valid
      validate :constrained_props

      private

      def type_is_known
        return if Websites::SectionKit.known?(type)

        errors.add(:type, I18n.t("website.errors.unknown_section"))
      end

      def hrefs_valid
        each_href(props_hash) do |value|
          next if Websites::Href.valid?(value)

          errors.add(:props, Websites::Href.error_message(value))
        end
      end

      def props_are_well_formed
        return unless Websites::SectionKit.known?(type)

        messages = Websites::PropSchema.validation_errors(type, props).flat_map { |violation| schema_messages(violation) }
        messages.uniq.each { |message| errors.add(:props, message) }
      end

      def schema_messages(violation)
        schema = violation["schema"]
        if %w[minItems maxItems].include?(violation["type"]) && schema.is_a?(Hash)
          return [array_count_message(violation["data_pointer"], schema)]
        end
        if violation["type"] == "required" && schema.is_a?(Hash)
          return Array(violation.dig("details", "missing_keys")).map do |key|
            bounds = schema.fetch("properties").fetch(key)
            array_count_message("#{violation['data_pointer']}/#{key}", bounds)
          end
        end

        [I18n.t("website.errors.invalid_props")]
      end

      def array_count_message(pointer, schema)
        name = pointer.split("/").last
        label_key = Websites::SectionFields::LABEL_KEYS[name]
        field = label_key ? I18n.t(label_key) : name
        I18n.t("website.errors.array_count", field: field, min: schema.fetch("minItems"), max: schema.fetch("maxItems"))
      end

      # Every select in the type's editor schema — top-level or inside a
      # list item — must hold one of its options (blank means "default").
      def constrained_props
        return if errors[:props].present?

        hash = props_hash
        Websites::SectionFields.full_schema_for(type).each do |field|
          if field[:kind] == :select
            check_option(field, hash[field[:key]])
          elsif field[:kind] == :array
            selects = field[:item_fields].select { |item| item[:kind] == :select }
            Array(hash[field[:key]]).each do |item|
              values = item.respond_to?(:to_h) ? item.to_h.stringify_keys : {}
              selects.each { |select| check_option(select, values[select[:key]]) }
            end
          end
        end
        check_styles(hash[Websites::SectionStyles::PROP])
      end

      def check_styles(styles)
        return if styles.blank?
        return errors.add(:props, :inclusion) unless styles.is_a?(Hash)

        kinds = Websites::SectionStyles.target_kinds(type)
        styles.each do |target, attrs|
          next errors.add(:props, :inclusion) unless kinds.key?(target) && attrs.is_a?(Hash)

          attrs.each do |attribute, value|
            next if value.blank? || Websites::SectionStyles.valid_value?(kinds.fetch(target), attribute, value)

            errors.add(:props, :inclusion)
          end
        end
      end

      def check_option(field, value)
        return if value.blank? || field[:options].include?(value.to_s)

        errors.add(:props, :inclusion)
      end

      def props_hash
        props.is_a?(Hash) ? props.deep_stringify_keys : {}
      end

      def each_href(obj, &block)
        case obj
        when Hash
          obj.each do |key, value|
            if Websites::SectionKit::HREF_KEYS.include?(key.to_s)
              yield value
            else
              each_href(value, &block)
            end
          end
        when Array
          obj.each { |value| each_href(value, &block) }
        end
      end
    end
  end
end
