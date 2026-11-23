# frozen_string_literal: true

module FeatureModules
  module Sms
    # Per-tenant provisioning hook — no-op because the SMS module's
    # credentials and templates are app-scoped. Per-tenant config
    # (daily_send_cap) lives on FeatureModules::CustomerAssignment.configuration
    # and is edited on the Settings/SMS module-config page (see
    # Registration.configuration_schema / configuration_keys), not here.
    class Provisioner
      def self.call(_customer) = nil
      def self.revoke(_customer) = nil
    end
  end
end
