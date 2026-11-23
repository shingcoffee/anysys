# frozen_string_literal: true

module FeatureModules
  module Email
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "email"
      def self.module_name        = "Email"
      def self.module_description = "Transactional and marketing email delivery"

      def self.provision!(customer)   = Provisioner.call(customer)
      def self.deprovision!(customer) = Provisioner.revoke(customer)

      # Per-tenant config surfaced by the generic Settings/Email page. The daily
      # send cap is read by Emails::Activities::Send#daily_cap_for; without this
      # schema the "Daily Cap" settings entry rendered an empty form and the cap
      # could only be set via console/seed. Keep descriptions out of the schema —
      # it is serialized to JSON at boot, so an I18n.t here would freeze at the
      # boot locale (the field label is localized in the view instead).
      def self.configuration_schema
        {
          "daily_send_cap" => { "type" => "number", "default" => ::Emails::Activities::Send::DEFAULT_DAILY_CAP }
        }
      end

      def self.configuration_keys
        %i[daily_send_cap]
      end

      def self.owner_managed_configuration_keys = %i[daily_send_cap]

      entry_path { |customer| "/#{customer.id}/admin/modules/emails/templates" }
      default_exit kind: "route", name: "customer_home"

      input_contract do
        property :to,           validates: { presence: true, format: { with: URI::MailTo::EMAIL_REGEXP } }
        property :template_id,  validates: { presence: true }
        property :vars,         validates: { presence: true }
        property :cc
        property :bcc
        property :reply_to
        property :idempotency_key
      end

      output_contract do
        property :message_id, validates: { presence: true }
        property :status,     validates: { inclusion: { in: %w[queued sent failed] } }
      end

      def self.sidebar_contributions(context)
        customer = context&.current_customer
        base = "/#{customer.id}/admin/modules/emails"

        {
          entries: [
            entry("send_activities", "#{base}/send_activities", tab_paths: %w[send_activities]),
            entry("audience", "#{base}/lists", tab_paths: %w[lists suppressions]),
            entry("content", "#{base}/templates", tab_paths: %w[templates]),
            entry("analytics", "#{base}/dashboard",
                  tab_paths: %w[dashboard health reports deliverability engagement])
          ],
          settings: [
            ModuleContribution.new(label: I18n.t("feature_modules.email.settings.daily_cap"), entry_key: "daily_cap"),
            ModuleContribution.new(
              label: I18n.t("feature_modules.email.settings.template_tokens"),
              entry_key: "template_tokens",
              path: ->(cid) { "/#{cid}/admin/settings/modules/emails/template_tokens" }
            )
          ]
        }
      end

      # tab_paths: sibling route segments (relative to the emails module base path) that
      # share this sidebar entry via in-page tabs, so the entry stays highlighted active
      # while the customer is on any of those tabs.
      def self.entry(key, path, tab_paths: nil)
        base = path.sub(%r{/[^/]+\z}, "")
        match_prefix = tab_paths&.map { |segment| "#{base}/#{segment}" }
        ModuleContribution.new(
          label: I18n.t("feature_modules.email.entries.#{key}"), entry_key: key,
          path: ->(_cid) { path }, match_prefix: match_prefix
        )
      end

      def self.entries_for(entry_key:, params:)
        case entry_key
        when "templates"       then templates_entry_config
        when "send_activities" then send_activities_entry_config
        when "lists"           then lists_entry_config
        else raise ArgumentError, "unknown entry_key: #{entry_key}"
        end
      end

      class << self
        private

        def templates_entry_config
          {
            title: I18n.t("feature_modules.email.titles.templates"),
            columns: [
              { key: :name, label: I18n.t("common.labels.name"), searchable: true },
              { key: :subject, label: I18n.t("common.labels.subject") },
              { key: :status, label: I18n.t("common.labels.status"), sortable: true }
            ],
            scope: ::Emails::Template.for_current_customer.order(created_at: :desc)
          }
        end

        def send_activities_entry_config
          {
            title: I18n.t("feature_modules.email.titles.send_activities"),
            columns: [
              { key: :name, label: I18n.t("common.labels.name"), searchable: true },
              { key: :status, label: I18n.t("common.labels.status"), sortable: true },
              { key: :scheduled_at, label: I18n.t("common.labels.scheduled"), sortable: true }
            ],
            scope: ::Emails::SendActivities::SendActivity.for_current_customer.order(created_at: :desc)
          }
        end

        def lists_entry_config
          {
            title: I18n.t("feature_modules.email.titles.lists"),
            columns: [
              { key: :name, label: I18n.t("common.labels.name"), searchable: true },
              { key: :description, label: I18n.t("common.labels.description") }
            ],
            scope: ::Emails::Audience::List.for_current_customer.order(created_at: :desc)
          }
        end
      end
    end
  end
end
