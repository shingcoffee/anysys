# frozen_string_literal: true

require "reform/form"

module Sms
  module Contracts
    class Send < Reform::Form
      # Lightweight backing object for a fresh send (avoids pulling in OpenStruct).
      Input = Struct.new(:to, :template_key, :vars, :idempotency_key)
      MAX_KEY_BYTES = SendStandards::MAX_KEY_BYTES
      MAX_VALUE_BYTES = SendStandards::MAX_VALUE_BYTES
      MAX_PAYLOAD_BYTES = SendStandards::MAX_PAYLOAD_BYTES
      MAX_VARIABLES = SendStandards::MAX_VARIABLES

      property :to
      property :template_key
      property :vars
      property :idempotency_key

      validate  :input_shapes
      validate  :template_exists_and_active
      validate  :vars_shape_matches_template

      def template
        return unless shapes_valid?

        @template ||= Sms::Template.active.find_by(key: template_key)
      end

      def validate(params)
        @template = nil
        normalized = params.dup
        normalized[:vars] = {} if normalized[:vars].nil? && !normalized.key?("vars")
        normalized["vars"] = {} if normalized.key?("vars") && normalized["vars"].nil?
        key = normalized.key?("idempotency_key") ? "idempotency_key" : :idempotency_key
        value = normalized[key]
        if value.is_a?(String) && SendStandards.idempotency_key_valid?(value) && value.blank?
          normalized[key] = nil
        end
        super(normalized)
      end

      private

      # Run all shape gates before any template SQL or provider access. Limits
      # refer to UTF-8 bytes and JSON wire bytes (including escaped characters).
      def input_shapes
        shape_errors.each { |attribute, message| errors.add(attribute, message) }
      end

      def shapes_valid?
        shape_errors.empty?
      end

      def shape_errors
        SendStandards.validation_errors(to: to, template_key: template_key, vars: vars, idempotency_key: idempotency_key)
      end

      def template_exists_and_active
        return unless shapes_valid?
        return if template.present?
        errors.add(:template_key, I18n.t("admin_modules.errors.validations.template_not_active"))
      end

      def vars_shape_matches_template
        return unless template
        provided = (vars.is_a?(Hash) ? vars : {}).keys.map(&:to_s)
        required = template.required_vars.map(&:to_s)
        missing  = required - provided
        extra    = provided - required
        errors.add(:vars, I18n.t("admin_modules.errors.validations.missing_required_keys", keys: missing.join(", "))) if missing.any?
        errors.add(:vars, I18n.t("admin_modules.errors.validations.unknown_keys", keys: extra.join(", ")))            if extra.any?
      end
    end
  end
end
