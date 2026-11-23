# frozen_string_literal: true

module Pages
  # Read-only summary of the records a page's locked inputs are filled with,
  # e.g. "Student — Alice Wang" on the step that adds her courses. +bindings+
  # come from Pages::InputBindings, already checked for this tenant and viewer.
  class LockedInputsComponent < ApplicationComponent
    Item = Data.define(:label, :value)

    def initialize(page:, bindings:)
      @page = page
      @records = bindings.respond_to?(:records) ? bindings.records : {}
      @bindings = bindings.to_h
    end

    def render? = items.any?

    def items
      @items ||= @page.page_inputs.filter_map do |input|
        id = @bindings[input["field"]]
        attribute = reference_attribute(input["field"])
        next if id.blank? || attribute.nil?

        Item.new(label: attribute["name"].to_s, value: record_label(input, attribute, id))
      end
    end

    private

    def reference_attribute(slug)
      Array(@page.entity&.property_schema_json).grep(Hash).find { |attribute| attribute["name_slug"] == slug }
    end

    def record_label(input, attribute, id)
      entry = @records[input["field"]] || EntityEntry.find_by(id: id, customer_id: Current.customer_id, entity_id: input["entity_id"])
      picker = Entities::BridgeParticipants.pickers([attribute], customer_id: Current.customer_id).first
      label_field = picker.dig("config", "label_field").to_s
      Entities::ReferenceLabels.text(entry&.data_json.to_h[label_field], id)
    end
  end
end
