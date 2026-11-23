# frozen_string_literal: true

module PageBuilder
  class FieldCardComponent < ApplicationComponent
    attr_reader :field

    def initialize(field:)
      @field = field
    end

    delegate :[], to: :field

    def field_id
      field["id"]
    end

    def label
      field["label"]
    end

    def placeholder
      field["placeholder"]
    end

    def required?
      field["required"]
    end

    def width
      field["width"] || "full"
    end

    def property_type
      field["property_type"]
    end

    private

    def wrapper_classes
      base = "field-card bg-white border border-gray-200 rounded-lg p-4 cursor-move hover:border-indigo-300 hover:shadow-sm transition-all"
      case width
      when "half" then "w-1/2 inline-block align-top pr-2 #{base}"
      when "third" then "w-1/3 inline-block align-top pr-2 #{base}"
      else "w-full #{base}"
      end
    end
  end
end
