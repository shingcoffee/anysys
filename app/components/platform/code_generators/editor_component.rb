# frozen_string_literal: true

module Platform
  module CodeGenerators
    # Metadata lives in the body's `generator_metadata` block; there are no
    # separate metadata fields to keep in sync.
    class EditorComponent < ApplicationComponent
      def initialize(generator_class:, path:, customer_id:, methods_body:, errors: [])
        @generator_class = generator_class
        @path = path
        @customer_id = customer_id
        @methods_body = methods_body
        @errors = Array(errors)
      end

      private

      attr_reader :generator_class, :methods_body, :errors

      def generator_name
        generator_class.generator_name
      end

      def version
        generator_class._metadata&.dig(:version)
      end

      def class_declaration
        "class #{generator_class.name} < CodeGenerators::BaseGenerator"
      end

      def form_url
        helpers.admin_maintenance_platform_code_generator_path(@customer_id, slug: @path)
      end

      def validation_url
        helpers.admin_maintenance_platform_code_generator_validation_path(@customer_id, code_generator_slug: @path)
      end
    end
  end
end
