# frozen_string_literal: true

module Websites
  module Sections
    class ContactInfoComponent < Websites::SectionComponent
      FIELDS = %w[address email hours phone].freeze

      def fields
        @fields ||= FIELDS.filter_map do |key|
          value = props[key].to_s
          next unless present_text?(value)

          { key: key, value: value, href: field_href(key, value) }
        end
      end

      def email_field
        fields.find { |field| field[:key] == "email" }
      end

      def field_label(key)
        I18n.t("website.public.contact.#{key}")
      end

      private

      def field_href(key, value)
        case key
        when "email" then "mailto:#{value.strip}"
        when "phone" then "tel:#{value.gsub(/[^\d+]/, "")}"
        end
      end
    end
  end
end
