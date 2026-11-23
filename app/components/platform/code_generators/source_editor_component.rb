# frozen_string_literal: true

module Platform
  module CodeGenerators
    class SourceEditorComponent < ApplicationComponent
      def initialize(name:, value:, label:, id: "generator-source-editor", fill: false)
        @name = name
        @value = value.to_s
        @label = label
        @id = id
        @fill = fill
      end

      private

      attr_reader :name, :value, :label, :id

      def height_class
        @fill ? "h-full" : "h-[32rem]"
      end

      def initial_line_numbers
        (1..[value.lines.count, 1].max).to_a.join("\n")
      end
    end
  end
end
