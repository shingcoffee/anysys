# frozen_string_literal: true

module Payments
  module Admin
    # Renders the dynamic credential-field section for a gateway config form.
    # Used by GatewayConfigComponent to show vendor-specific credential inputs.
    #
    #   fields — array of { name:, label:, type: (:string|:password|:text), encrypted: bool }
    #            typically from Payments::Gateways::<Vendor>.credential_fields
    class CredentialFieldsComponent < ApplicationComponent
      attr_reader :account, :fields

      def initialize(account:, fields:)
        @account = account
        @fields  = fields
      end

      # For existing records we show a placeholder for encrypted fields rather
      # than the actual plaintext. The admin retypes if they want to change it.
      def encrypted_placeholder(field)
        return "" unless account.persisted?
        return "" unless field[:encrypted]

        account.credential(field[:name]).present? ? "••••••••" : ""
      end

      def field_value(field)
        return "" if field[:encrypted]

        account.credential(field[:name]).to_s
      end

      # Show the "leave blank to keep" hint only on edit (persisted) records for
      # encrypted fields.
      def show_keep_hint?(field)
        account.persisted? && field[:encrypted] && account.credential(field[:name]).present?
      end

      def field_label(field)
        I18n.t("settings_modules.payments.credentials.#{account.provider}.#{field[:name]}",
          default: I18n.t("settings_modules.payments.credential_fallback", number: fields.index(field) + 1))
      end
    end
  end
end
