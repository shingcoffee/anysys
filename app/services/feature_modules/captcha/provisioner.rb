# frozen_string_literal: true

module FeatureModules
  module Captcha
    class Provisioner
      def self.call(_customer)
        nil
      end

      def self.deprovision(customer)
        Page.unscoped.where(customer_id: customer.id).find_each do |page|
          config = page.configuration_json
          next unless config.is_a?(Hash) && config.key?("captcha")

          config = config.except("captcha")
          page.configuration_json = config
          page.save!(validate: false)
        end
      end
    end
  end
end
