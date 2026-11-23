# frozen_string_literal: true

# Authentication::Settings
#
# Read-only value object that exposes per-customer authentication toggles
# (sign-up, password reset, MFA) and effective session/lockout policy. Wraps
# `customer_feature_modules.configuration` so controllers and views never
# reach into the feature-module schema directly.
#
# Usage:
#   auth_settings = Authentication::Settings.for(customer_id)
#   auth_settings.signup_enabled?
#   auth_settings.password_reset_enabled?
#
module Authentication
  class Settings
    def self.for(customer_id)
      new(customer_id)
    end

    def initialize(customer_id)
      @customer_id = customer_id
    end

    def signup_enabled?
      module_active? && bool(config["allow_registration"], default: false)
    end

    def password_reset_enabled?
      module_active? && bool(config["allow_password_reset"], default: true)
    end

    def mfa_enabled?
      module_active? && bool(config["mfa_enabled"], default: false)
    end

    def timeout_in(default:)
      minutes = positive_integer("session_timeout")
      minutes ? minutes.minutes : default
    end

    def maximum_attempts(default:)
      positive_integer("max_login_attempts") || default
    end

    private

    # Stored form values may be strings or JSON integers. Invalid, omitted or
    # inactive settings retain the resource class's current Devise default.
    def positive_integer(key)
      return unless module_active?

      value = config[key]
      number = case value
      when Integer then value
      when String then Integer(value.strip, 10) if value.strip.match?(/\A\d+\z/)
      end
      number if number&.positive?
    end

    def module_active?
      assignment&.active? || false
    end

    def config
      @config ||= assignment&.configuration_json || {}
    end

    def assignment
      return @assignment if defined?(@assignment)
      return @assignment = nil if @customer_id.blank?

      fm = FeatureModules::Module.find_by(key: "authentication")
      return @assignment = nil unless fm

      @assignment = FeatureModules::CustomerAssignment.find_by(
        customer_id: @customer_id, feature_module_id: fm.id
      )
    end

    def bool(value, default:)
      return default if value.nil?
      return value if value == true || value == false

      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
