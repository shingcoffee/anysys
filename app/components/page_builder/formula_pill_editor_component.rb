# frozen_string_literal: true

module PageBuilder
  class FormulaPillEditorComponent < ApplicationComponent
    include ComponentClasses

    def initialize(formula: "", fields: [], embedded: false)
      @formula = formula.to_s
      @embedded = embedded
      @fields = (fields || []).map do |f|
        { "id" => f["id"], "label" => f["label"] || f["id"], "type" => f["property_type"] }
      end
    end

    private

    attr_reader :formula, :fields, :embedded

    def fields_json
      fields.to_json
    end
  end
end
