# frozen_string_literal: true

module Websites
  # Schema for the reserved `styles` section prop: which targets a section
  # type exposes to the builder's Design panel, which attributes each target
  # kind accepts, and which values are valid. Stored shape:
  #   { "headline" => { "color" => "accent", "size" => "xl" }, "cards" => { "background" => "#f5efe6" } }
  module SectionStyles
    PROP = "styles"

    COLOR_TOKENS = %w[accent ink body muted inverse].freeze
    BACKGROUND_TOKENS = %w[band accent_soft accent ink canvas].freeze
    SCALES = { "xs" => 0.75, "sm" => 0.875, "lg" => 1.125, "xl" => 1.25, "2xl" => 1.5 }.freeze
    WEIGHTS = { "regular" => 400, "medium" => 500, "semibold" => 600, "bold" => 700 }.freeze
    ITALICS = %w[italic normal].freeze
    ALIGNS = %w[start center end].freeze
    SHAPES = %w[pill rounded square].freeze
    # Curated swatches offered beside the theme tokens; any #rrggbb is valid.
    PALETTE = %w[
      #0f172a #1e3a8a #0e7490 #047857 #4d7c0f #b45309 #c2410c #be123c #a21caf #6d28d9
      #f5efe6 #eef2f6 #fbeff1 #ecf7f1 #fdf6e3 #ffffff
    ].freeze
    HEX = /\A#\h{6}\z/

    ATTRIBUTES = {
      section: %w[background heading_font body_font scale],
      element: %w[color font size weight italic align],
      buttons: %w[shape fill text],
      items: %w[background text]
    }.freeze

    BUTTON_LABELS = %w[primary_label secondary_label button_label].freeze

    module_function

    # [{ key:, kind:, field:, array: }] in editor order.
    def targets_for(type)
      return [] unless SectionKit.known?(type)

      schema = SectionFields.schema_for(type)
      targets = [{ key: "section", kind: :section }]
      schema.each do |field|
        targets << { key: field[:key], kind: :element, field: field[:key] } if text_field?(field)
      end
      targets << { key: "buttons", kind: :buttons } if schema.any? { |field| BUTTON_LABELS.include?(field[:key]) }
      schema.select { |field| field[:kind] == :array }.each do |array|
        targets << { key: array[:key], kind: :items, array: array[:key] }
        array[:item_fields].each do |field|
          next unless text_field?(field)

          targets << { key: "#{array[:key]}.#{field[:key]}", kind: :element, array: array[:key], field: field[:key] }
        end
      end
      targets
    end

    def target_kinds(type)
      targets_for(type).to_h { |target| [target[:key], target[:kind]] }
    end

    def text_field?(field)
      key = field[:key].to_s
      %i[string textarea].include?(field[:kind]) &&
        !SectionKit::HREF_KEYS.include?(key) && !SectionKit::IMAGE_KEYS.include?(key) && !BUTTON_LABELS.include?(key)
    end

    def valid_value?(kind, attribute, value)
      return false unless ATTRIBUTES.fetch(kind.to_sym, []).include?(attribute.to_s)

      v = value.to_s
      case attribute.to_s
      when "color", "fill", "text" then COLOR_TOKENS.include?(v) || hex?(v)
      when "background" then kind.to_sym == :section ? hex?(v) : (BACKGROUND_TOKENS.include?(v) || hex?(v))
      when "font", "heading_font", "body_font" then Fonts.known?(v)
      when "size", "scale" then SCALES.key?(v)
      when "weight" then WEIGHTS.key?(v)
      when "italic" then ITALICS.include?(v)
      when "align" then ALIGNS.include?(v)
      when "shape" then SHAPES.include?(v)
      else false
      end
    end

    def hex?(value)
      HEX.match?(value.to_s)
    end

    # Drops unknown targets/attributes, invalid and blank values.
    def sanitize(type, raw)
      kinds = target_kinds(type)
      hash = raw.respond_to?(:to_h) ? raw.to_h.deep_stringify_keys : {}
      hash.each_with_object({}) do |(target, attrs), clean|
        kind = kinds[target]
        next unless kind && attrs.respond_to?(:to_h)

        values = attrs.to_h.select { |attribute, value| value.present? && valid_value?(kind, attribute, value) }
        clean[target] = values.transform_values(&:to_s) if values.any?
      end
    end

    # json_schemer fragment for PropSchema: only this type's targets/attributes.
    def json_schema(type)
      {
        "type" => %w[object null],
        "additionalProperties" => false,
        "properties" => targets_for(type).to_h do |target|
          [target[:key], {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => ATTRIBUTES.fetch(target[:kind]).to_h { |attribute| [attribute, { "type" => %w[string null] }] }
          }]
        end
      }
    end

    # Font families picked by any section style override (for the stylesheet).
    def font_keys(sections)
      Array(sections).flat_map do |section|
        hash = section.respond_to?(:to_h) ? section.to_h.stringify_keys : {}
        props = hash["props"].respond_to?(:to_h) ? hash["props"].to_h.stringify_keys : {}
        styles = props[PROP].respond_to?(:to_h) ? props[PROP].to_h : {}
        styles.values.flat_map do |attrs|
          next [] unless attrs.respond_to?(:to_h)

          attrs.to_h.stringify_keys.values_at("font", "heading_font", "body_font").compact.map(&:to_s)
        end
      end.select { |key| Fonts.known?(key) }.uniq
    end
  end
end
