# frozen_string_literal: true

module FeatureModules
  module Website
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "website"
      def self.module_name        = "Website"
      def self.module_description = "Customer introduction and marketing website — static pages, no forms"

      def self.provision!(customer)   = Provisioner.call(customer)
      def self.deprovision!(customer) = Provisioner.deprovision(customer)

      def self.configuration_schema
        {
          "default_skeleton_key" => { "type" => "string", "default" => "presence" }
        }
      end

      entry_path { |customer| "/#{customer.id}/admin/modules/website" }

      def self.sidebar_contributions(_controller)
        {
          entries: [
            ModuleContribution.new(
              label: I18n.t("feature_modules.website.entries.pages"),
              entry_key: "pages",
              path: ->(cid) { "/#{cid}/admin/modules/website" }
            )
          ],
          settings: [
            ModuleContribution.new(
              label: I18n.t("feature_modules.website.settings.site"),
              entry_key: "site",
              path: ->(cid) { "/#{cid}/admin/settings/modules/website" }
            )
          ]
        }
      end

      def self.entries_for(entry_key:, params:)
        case entry_key.to_s
        when "pages"
          {
            title: I18n.t("website.admin.pages.index.title"),
            columns: [
              { key: :title, label: I18n.t("website.admin.pages.index.columns.title"), searchable: true },
              { key: :slug, label: I18n.t("website.admin.pages.index.columns.slug") },
              { key: :published, label: I18n.t("website.admin.pages.index.columns.published"), sortable: true },
              { key: :nav_visible, label: I18n.t("website.admin.pages.index.columns.nav") },
              { key: :home, label: I18n.t("website.admin.pages.index.columns.home") },
              { key: :updated_at, label: I18n.t("website.admin.pages.index.columns.updated"), sortable: true }
            ],
            scope: ::WebsitePage.for_current_customer.order(:position)
          }
        else
          raise ArgumentError, "unknown entry_key: #{entry_key}"
        end
      end
    end
  end
end
