# frozen_string_literal: true

module FeatureModules
  module Website
    class Provisioner
      class ProvisioningError < StandardError; end

      def self.call(customer)
        result = Websites::Activities::Provision.call(customer: customer)
        unless result.success?
          raise ProvisioningError, Array(result.errors).join(", ").presence || I18n.t("maint_core.flash.module_enablements.enable_failed")
        end

        result.model
      end

      def self.deprovision(customer)
        site = ::Website.for_customer(customer.id).first
        site&.update!(published: false)
        site
      end
    end
  end
end
