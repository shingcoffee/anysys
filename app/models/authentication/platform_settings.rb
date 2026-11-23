# frozen_string_literal: true

module Authentication
  # Singleton platform-owner knobs for authentication. Survives feature-module
  # `register!` schema rewrites. Seeded on first read with customer sign-up on.
  class PlatformSettings < ApplicationRecord
    self.table_name = "authentication_platform_settings"

    def self.instance
      first || create!(allow_customer_signup: true)
    end

    def self.customer_signup_enabled?
      instance.allow_customer_signup?
    end
  end
end
