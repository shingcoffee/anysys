# frozen_string_literal: true

module Platform
  module CodeGenerators
    class IndexToolbarComponent < ApplicationComponent
      def initialize(customer_id:, total_count:)
        @customer_id = customer_id
        @total_count = total_count
      end

      private

      attr_reader :customer_id, :total_count

      def back_path
        helpers.admin_maintenance_path(customer_id)
      end

      def new_generator_path
        helpers.new_admin_maintenance_platform_code_generator_path(customer_id, kind: "step_action")
      end
    end
  end
end
