# frozen_string_literal: true

module Platform
  module CodeGenerators
    class DetailComponent < ApplicationComponent
      TAB_BASE = "-mb-px inline-flex items-center gap-1.5 whitespace-nowrap border-b-2 px-3 py-2 text-sm font-medium transition-colors"
      TAB_ACTIVE = "border-accent text-text-primary"
      TAB_INACTIVE = "border-transparent text-text-muted hover:text-text-primary"

      def initialize(generator_class:, source_code:, path:, customer_id:)
        @generator_class = generator_class
        @source_code = source_code
        @path = path
        @customer_id = customer_id
      end

      private

      attr_reader :generator_class, :source_code

      def metadata
        generator_class._metadata || {}
      end

      def generator_name
        generator_class.generator_name
      end

      def kind_label
        kind = generator_class.generator_kind == :element_type ? "element_type" : "step_action"
        t("comp_platform.code_generators.form.kind_#{kind}")
      end

      def category_label
        category = metadata[:category].to_s
        t("comp_platform.code_generators.category.#{category}", default: category) if category.present?
      end

      def aliases
        Array(generator_class.registered_names) - [generator_name]
      end

      def file_path
        "app/services/code_generators/#{@path}.rb"
      end

      def sample_config
        generator_class.sample_input || {}
      end

      def sample_json
        JSON.pretty_generate(sample_config)
      end

      def run
        @run ||= begin
          { result: ::CodeGenerators::TestRunner.run(generator_class, config: sample_config) }
        rescue StandardError => e
          { error: e.message }
        end
      end

      def io
        result = run[:result] || {}
        { inputs: Array(result[:inputs]), outputs: Array(result[:outputs]) }
      end

      def dependencies
        generator_class.new({}, {}).dependencies
      rescue StandardError
        []
      end

      def schema_fields
        generator_class._config_schema&.fields || []
      end

      def line_count
        source_code.lines.count
      end

      def test_run_path
        helpers.admin_maintenance_platform_code_generator_test_run_path(@customer_id, code_generator_slug: @path)
      end

      def edit_path
        helpers.edit_admin_maintenance_platform_code_generator_path(@customer_id, slug: @path)
      end

      def tabs
        [
          { id: "playground", label: t("comp_platform.code_generators.detail.tab_playground") },
          { id: "schema", label: t("comp_platform.code_generators.detail.tab_schema"), meta: schema_fields.size },
          { id: "source", label: t("comp_platform.code_generators.detail.source_code"),
            meta: t("comp_platform.code_generators.lines_count", count: line_count) }
        ]
      end

      def tab_classes(active)
        [TAB_BASE, active ? TAB_ACTIVE : TAB_INACTIVE].join(" ")
      end
    end
  end
end
