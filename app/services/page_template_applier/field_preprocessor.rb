# frozen_string_literal: true

class PageTemplateApplier
  # Handles early-stage field transformations that run before any grouping:
  #   - splitting layout vs. entity fields
  #   - audience-based visibility filtering
  #   - width rule assignment
  #   - mobile-stack responsive width injection
  class FieldPreprocessor
    def initialize(fields)
      @fields = fields
    end

    # Splits @fields into section_headers (property_type == "layout") and
    # entity_fields (everything else).
    # Returns { section_headers: [...], entity_fields: [...] }.
    def separate
      section_headers = []
      entity_fields   = []

      @fields.each do |field|
        if field["property_type"] == "layout"
          section_headers << field
        else
          entity_fields << field
        end
      end

      { section_headers: section_headers, entity_fields: entity_fields }
    end

    # Removes fields whose visibility[audience] is explicitly false.
    # Mutates +fields+ in place. No-op when layout[:audience] is nil.
    def apply_visibility_filter!(fields, layout)
      audience = layout[:audience]
      return if audience.nil?

      audience_str = audience.to_s
      audience_sym = audience.to_sym

      fields.reject! do |f|
        v = f["visibility"]
        next false unless v.is_a?(Hash)

        v[audience_str] == false || v[audience_sym] == false
      end
    end

    # Assigns field["width"] from the layout's field_width_rules (keyed by
    # html_type) or falls back to layout[:default_width] (default "full").
    # Mutates each field in place.
    def apply_width_rules(fields, layout)
      rules   = layout[:field_width_rules] || {}
      default = layout[:default_width] || "full"

      fields.each do |field|
        html_type       = field["html_type"].to_s
        field["width"]  = rules[html_type] || default
      end
    end

    # When layout[:mobile_stack] is true, injects responsive_widths["mobile"] =
    # "full" for every non-full-width, non-layout field that does not already
    # carry a mobile override.  Mutates each qualifying field in place.
    def apply_mobile_stack!(fields, layout)
      return unless layout[:mobile_stack]

      fields.each do |field|
        next if field["property_type"] == "layout"
        next if field["width"] == "full"

        existing      = field["responsive_widths"]
        existing_hash = existing.is_a?(Hash) ? existing : {}
        next if existing_hash.key?("mobile")

        field["responsive_widths"] = existing_hash.merge("mobile" => "full")
      end
    end
  end
end
