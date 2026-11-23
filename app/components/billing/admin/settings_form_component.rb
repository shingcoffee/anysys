# frozen_string_literal: true

module Billing
  module Admin
    # Renders the billing settings form (platform owner, Area d).
    # Issued collection policy is snapshotted; provider choice belongs to the
    # customer's verified default method, not a global provider field.
    #
    # Constructor:
    #   settings:    Billing::Settings instance
    #   customer_id: current customer_id (owner's) for route helpers
    #   mode:        :show or :edit
    class SettingsFormComponent < ApplicationComponent
      include Presentation

      def initialize(settings:, customer_id:, mode: :show, form: nil)
        @settings    = settings
        @customer_id = customer_id.to_s
        @mode        = mode.to_sym
        @form = form || Billing::Contracts::Settings.new(settings)
      end

      attr_reader :settings, :customer_id, :mode
      attr_reader :form
      def form_record = settings
      def form_scope = "billing_settings"

      def edit? = mode == :edit

      def form_url
        helpers.admin_maintenance_platform_billing_settings_path(customer_id)
      end

      def collection_mode_options
        submitted_options(Billing::Settings::COLLECTION_MODES.map { |mode| [I18n.t("comp_billing.settings_form.collection_modes.#{mode}"), mode] }, :collection_mode)
      end

      def collection_mode_label
        I18n.t("comp_billing.settings_form.collection_modes.#{settings.collection_mode}")
      end

      def tax_rate_percent
        helpers.number_with_precision(settings.tax_rate_bps / 100.0, precision: 2, strip_insignificant_zeros: true)
      end

      def dunning_days
        Array(settings.dunning_schedule)
      end

      def dunning_schedule_display
        value = form_value(:dunning_schedule)
        value.is_a?(Array) ? value.join(", ") : value
      end
    end
  end
end
