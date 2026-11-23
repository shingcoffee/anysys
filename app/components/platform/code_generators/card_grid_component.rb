# frozen_string_literal: true

module Platform
  module CodeGenerators
    class CardGridComponent < ApplicationComponent
      def initialize(generators:, category_label:, customer_id:, category_icon: nil, category_count: 0)
        @generators = generators
        @category_label = category_label
        @customer_id = customer_id
        @category_icon = category_icon
        @category_count = category_count
      end

      def generator_path(name, klass)
        relative = klass.name
                       .delete_prefix("CodeGenerators::")
                       .underscore
                       .gsub("::", "/")
        helpers.admin_maintenance_platform_code_generator_path(@customer_id, slug: relative)
      end

      def generator_io(klass)
        result = ::CodeGenerators::TestRunner.run(klass, config: klass.sample_input)
        { inputs: result[:inputs], outputs: result[:outputs] }
      rescue StandardError
        { inputs: [], outputs: [] }
      end
    end
  end
end
