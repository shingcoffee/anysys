# frozen_string_literal: true

module FeatureModules
  module Sms
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "sms"
      def self.module_name        = "SMS"
      def self.module_description = I18n.t("sms_campaign_http.registration.description")

      def self.provision!(customer)   = Provisioner.call(customer)
      def self.deprovision!(customer) = Provisioner.revoke(customer)

      # Per-tenant config surfaced by the generic Settings/SMS page. The daily
      # send cap is read by Sms::Activities::Send#daily_cap_for; without this
      # schema the Settings entry rendered an empty form and the cap could only
      # be set via console/seed. Keep descriptions out of the schema — it is
      # serialized to JSON at boot, so an I18n.t here would freeze at the boot
      # locale (the field label is localized in the view instead).
      def self.configuration_schema
        {
          "daily_send_cap" => { "type" => "number", "default" => ::Sms::Activities::Send::DEFAULT_DAILY_CAP }
        }
      end

      def self.configuration_keys
        %i[daily_send_cap]
      end

      def self.owner_managed_configuration_keys = %i[daily_send_cap]

      entry_path { |customer| "/#{customer.id}/admin/modules/sms/campaigns" }
      default_exit kind: "route", name: "customer_home"

      input_contract do
        property :to,             validates: { presence: true, format: { with: /\A\+?\d{7,15}\z/ } }
        property :template_key,   validates: { presence: true }
        property :vars
        property :idempotency_key
        property :expires_at
      end

      output_contract do
        property :message_id, validates: { presence: true }
        property :status,     validates: { inclusion: { in: ::Sms::Message::STATUSES } }
      end

      def self.sidebar_contributions(context)
        customer = context&.current_customer
        settings = [
          ModuleContribution.new(label: I18n.t("feature_modules.sms.settings.daily_cap"), entry_key: "daily_cap")
        ]
        return { entries: [], settings: settings } unless customer

        base = "/#{customer.id}/admin/modules/sms"
        {
          entries: [
            entry("campaigns", "#{base}/campaigns", %w[campaigns], "sms_campaign_http.navigation.campaigns"),
            entry("audience", "#{base}/contacts", %w[contacts segments opt_outs], "feature_modules.email.entries.audience"),
            entry("messages", "#{base}/messages", %w[messages], "feature_modules.sms.entries.messages")
          ],
          settings: settings
        }
      end

      # tab_paths: sibling route segments that share this sidebar entry via in-page tabs.
      def self.entry(key, path, segments, label_key)
        base = path.sub(%r{/[^/]+\z}, "")
        ModuleContribution.new(
          label: I18n.t(label_key), entry_key: key,
          path: ->(_cid) { path },
          match_prefix: segments.map { |segment| "#{base}/#{segment}" }
        )
      end

      def self.entries_for(entry_key:, params:)
        case entry_key
        when "messages" then messages_entry_config
        when "campaigns", "contacts", "segments"
          model = { "campaigns" => ::Sms::Campaign, "contacts" => ::Sms::Contact,
                    "segments" => ::Sms::Audience::Segment }.fetch(entry_key)
          {
            title: I18n.t("sms_campaign_http.navigation.#{entry_key}"),
            columns: [
              { key: :name, label: I18n.t("common.labels.name"), searchable: true, sortable: true },
              { key: :updated_at, label: I18n.t("common.labels.updated_at"), type: :datetime, sortable: true }
            ],
            scope: model.where(customer_id: Current.customer_id).order(updated_at: :desc)
          }
        else raise ArgumentError, "unknown entry_key: #{entry_key}"
        end
      end

      class << self
        private

        def messages_entry_config
          {
            title: I18n.t("feature_modules.sms.titles.messages"),
            columns: [
              { key: :created_at,   label: I18n.t("common.labels.at"),       sortable: true },
              { key: :to,           label: I18n.t("common.labels.to"),       searchable: true },
              { key: :template_key, label: I18n.t("common.labels.template") },
              { key: :status,       label: I18n.t("common.labels.status"),   sortable: true }
            ],
            scope: ::Sms::Message.for_current_customer.includes(:sms_template).order(created_at: :desc)
          }
        end
      end
    end
  end
end
