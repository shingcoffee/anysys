# frozen_string_literal: true

module FeatureModules
  module Captcha
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "captcha"
      def self.module_name        = "Captcha"
      def self.module_description = "Protect customer-facing public forms with a captcha vendor (Aliyun, etc.)"

      def self.provision!(customer)   = Provisioner.call(customer)
      def self.deprovision!(customer) = Provisioner.deprovision(customer)

      entry_path { |customer| "/#{customer.id}/admin/settings/modules/captcha" }
      default_exit kind: "route", name: "customer_home"

      def self.sidebar_contributions(_controller)
        {
          entries:  [],
          settings: [
            ModuleContribution.new(
              label:    I18n.t("feature_modules.captcha.settings.status"),
              entry_key: "status",
              path:     ->(cid) { "/#{cid}/admin/settings/modules/captcha" }
            )
          ]
        }
      end
    end
  end
end
