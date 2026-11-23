# frozen_string_literal: true

require "reform/form"

module Sms
  module Contracts
    class TemplatePreview < Reform::Form
      PLACEHOLDER = /\{\{([a-zA-Z0-9_]+)\}\}/
      Input = Struct.new(:purpose, :body_template, :variables, keyword_init: true)
      property :purpose
      property :body_template
      property :variables
      validate :preview_values

      private

      def preview_values
        errors.add(:purpose, I18n.t("sms_audience.errors.invalid_purpose")) unless Sms::Template::PURPOSES.include?(purpose)
        return if body_template.nil?
        valid = Bounds.text?(body_template, bytes: 4096) && variables.is_a?(Array) &&
          (body_template.scan(PLACEHOLDER).flatten - variables).empty? &&
          !body_template.gsub(PLACEHOLDER, "").match?(/\{\{|\}\}/)
        errors.add(:body_template, I18n.t("sms_audience.errors.invalid_body_template")) unless valid
      end
    end
  end
end
