# frozen_string_literal: true

module Platform
  module CodeGenerators
    class FormComponent < ApplicationComponent
      PROCESS_DIR = Rails.root.join("app/services/code_generators/element_types/process")

      def initialize(form_data:, customer_id:, kind: nil, errors: [])
        @form_data = form_data
        @customer_id = customer_id
        @kind = kind
        @errors = Array(errors)
      end

      private

      attr_reader :errors

      def form_url
        helpers.admin_maintenance_platform_code_generators_path(@customer_id)
      end

      def preview_source_url
        helpers.admin_maintenance_platform_source_preview_path(@customer_id)
      end

      def field(key)
        @form_data[key].to_s
      end

      def kind_selected?(kind)
        @kind == kind
      end

      def category_options
        categories = PROCESS_DIR.children.select(&:directory?).map { |dir| dir.basename.to_s }
        categories |= [field(:category)] if field(:category).present?
        categories.sort.map { |value| [t("comp_platform.code_generators.category.#{value}", default: value), value] }
      end
    end
  end
end
