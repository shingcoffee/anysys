# frozen_string_literal: true

module FeatureModules
  module TestModule
    class Registration < FeatureModules::BaseModule
      def self.module_key      = "test_module"
      def self.module_name     = "Test Module"
      def self.provision!(_c)  = nil
      def self.deprovision!(_c) = nil

      entry_path   { |customer| "/#{customer.id}/test_module/start" }
      default_exit kind: "route", name: "customer_home"

      input_contract do
        property :x, validates: { presence: true }
      end

      output_contract do
        property :ok, validates: { presence: true }
      end
    end
  end
end
