# frozen_string_literal: true

module Platform
  module CodeGenerators
    class SchemaTableComponent < ApplicationComponent
      def initialize(fields:)
        @fields = Array(fields)
      end

      private

      attr_reader :fields

      def default_text(field)
        default = field.options[:default]
        default.nil? ? nil : JSON.generate(default)
      end

      def required_text(field)
        return t("comp_platform.code_generators.schema.required_always") if field.options[:required]

        t("comp_platform.code_generators.schema.required_conditional") if conditions(field, :requires).any?
      end

      def shown_when(field)
        conditions(field, :visible).map { |rule| describe_rule(rule) }.join("; ").presence
      end

      def required_when(field)
        conditions(field, :requires).map { |rule| describe_rule(rule) }.join("; ").presence
      end

      def allowed_text(field)
        options = field.options
        return Array(options[:values]).join(", ") if options[:values]
        return if options[:min].nil? && options[:max].nil?

        "#{options[:min]}…#{options[:max]}"
      end

      def empty_value = t("comp_platform.code_generators.empty_value")

      def advanced?(field)
        field.options[:group] == :advanced
      end

      def conditions(field, type)
        field.conditions.select { |condition| condition[:type] == type }.map { |condition| condition[:when] }
      end

      def describe_rule(rule)
        rule.map { |name, values| "#{name} = #{Array(values).join(' | ')}" }.join(", ")
      end
    end
  end
end
