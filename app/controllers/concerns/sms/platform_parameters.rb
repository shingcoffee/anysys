# frozen_string_literal: true

module Sms
  module PlatformParameters
    extend ActiveSupport::Concern

    included do
      wrap_parameters false
      before_action :require_platform_sms_owner!
      before_action :check_platform_sms_body!, if: -> { request.post? || request.patch? || request.put? }
      rescue_from RequestAttributes::Invalid, with: :platform_input_error
    end

    private

    def require_platform_sms_owner!
      return if current_user&.platform_owner? && current_customer_id == Authentication::User::PLATFORM_CUSTOMER_ID

      raise CanCan::AccessDenied, t("common.errors.authorization.platform_owner_required")
    end

    def check_platform_sms_body!
      RequestAttributes.check_body!(request)
    end

    def platform_attributes(root, allowed:, objects: [])
      outer = RequestAttributes.action_inputs(request, allowed: [root])
      raw = outer[root.to_sym]
      raise RequestAttributes::Invalid.new(:base, :object_required) unless raw.is_a?(Hash)
      raise RequestAttributes::Invalid.new(:base, :unknown_parameters) if (raw.keys.map(&:to_sym) - allowed).any?

      raw.each do |key, value|
        if objects.include?(key.to_sym)
          unless value.is_a?(Hash) && value.values.all? { |item| item.is_a?(String) && item.valid_encoding? }
            raise RequestAttributes::Invalid.new(key, :object_required)
          end
        elsif !value.nil? && !(value.is_a?(String) && value.valid_encoding?) &&
              !(key.to_sym == :sender_rate_per_second && value.is_a?(Numeric))
          raise RequestAttributes::Invalid.new(key, :string_required)
        end
      end
      raw.symbolize_keys
    end

    def platform_input_error(error)
      @errors = error.errors
      record = @template || @credential
      @errors.each { |field, messages| messages.each { |message| record&.errors&.add(field, message) } }
      respond_to do |format|
        format.json { render json: { error: { code: error.code, errors: @errors } }, status: :unprocessable_entity }
        format.html do
          if record
            render action_name == "create" ? :new : :edit, status: :unprocessable_entity
          else
            render plain: @errors.values.flatten.join(" "), status: :unprocessable_entity
          end
        end
      end
    end
  end
end
