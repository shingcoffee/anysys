# frozen_string_literal: true

module Platform
  module CodeGenerators
    class ToolbarComponent < ApplicationComponent
      def initialize(generator_class:, path:, customer_id:)
        @generator_class = generator_class
        @path = path
        @customer_id = customer_id
      end

      private

      attr_reader :generator_class, :path, :customer_id

      def metadata
        generator_class&._metadata || {}
      end

      def generator_name
        generator_class&.generator_name || "unknown"
      end

      def category_label
        return "" if metadata[:category].blank?

        t("comp_platform.code_generators.category.#{metadata[:category]}")
      end

      def version
        metadata[:version]
      end

      def back_path
        helpers.admin_maintenance_platform_code_generators_path(customer_id)
      end

      def edit_path
        helpers.edit_admin_maintenance_platform_code_generator_path(customer_id, slug: path)
      end

      def delete_path
        helpers.admin_maintenance_platform_code_generator_path(customer_id, slug: path)
      end
    end
  end
end
