# frozen_string_literal: true

# Populates page builder canvas fields from an entity's field structure: one
# page tab holding the base model fields and the entity's own fields. Associated
# entities stay out of a generated page; their rows are linked from the entry
# afterwards.
#
# @example
#   pages = PageFieldPopulator.call(entity)
#   # => [{ "id" => "page_1", "name" => "Student", "order" => 1, "fields" => [...] }]
#
class PageFieldPopulator
  # Maps HTML types to property types for the page builder
  HTML_TYPE_TO_PROPERTY_TYPE = {
    "text"           => "string",
    "textarea"       => "string",
    "search"         => "string",
    "password"       => "string",
    "hidden"         => "string",
    "email"          => "string",
    "tel"            => "string",
    "url"            => "string",
    "color"          => "string",
    "number"         => "integer",
    "range"          => "integer",
    "checkbox"       => "boolean",
    "select"         => "string",
    "radio"          => "string",
    "date"           => "date",
    "time"           => "time",
    "datetime-local" => "datetime",
    "month"          => "string",
    "week"           => "string",
    "file"           => "string",
    "image"          => "string"
  }.freeze

  def self.call(entity)
    new(entity).call
  end

  def initialize(entity)
    @entity = entity
  end

  def call
    return [] unless @entity

    sections = EntityFieldOrganizer.primary(@entity)

    # Base model fields use "base_model" source and source_section is the model name,
    # so they are namespaced as base[model_name][slug] in the generated form and
    # routed to the corresponding base model record on save.
    base_fields = sections[:base_fields].flat_map do |model_name, fields|
      build_page_fields(fields, source: "base_model", source_section: model_name)
    end
    own_fields  = build_page_fields(sections[:own_fields], source: "entity", source_section: @entity.display_label)
    page_fields = base_fields + own_fields
    return [] if page_fields.empty?

    [{ "id" => "page_1", "name" => @entity.display_label, "order" => 1, "fields" => page_fields }]
  end

  private

  def build_page_fields(props, source:, source_section:)
    props.each_with_index.map do |prop, index|
      build_field(prop, index, source: source, source_section: source_section)
    end
  end

  def build_field(prop, order, source:, source_section:)
    html_type = prop["html_type"].presence || "text"
    field = {
      "id" => "field_#{SecureRandom.hex(8)}",
      "field_type" => html_type,
      "property_slug" => prop["name_slug"],
      "property_type" => normalize_property_type(html_type),
      "label" => prop["name"],
      "placeholder" => "",
      "help_text" => prop["description"].to_s,
      "required" => false,
      "width" => "full",
      "order" => order,
      "source" => source,
      "source_section" => source_section,
      "html_type" => html_type
    }

    field["group_id"] = prop["group_id"] if prop["group_id"].present?

    # Carry over defined options from entity property config
    options = prop.dig("config", "options")
    field["options"] = normalize_options(options) if options.is_a?(Array) && options.any?

    # Carry over dynamic options config for entity-entry dropdowns
    if prop.dig("config", "options_source") == "entity_entries"
      field["dynamic_options"] = prop["config"].slice("options_source", "entity_id", "label_field")
    end

    field
  end

  # Normalize options to consistent { "label" => ..., "value" => ... } format.
  # Handles both simple strings (from base model config) and hash objects (from entity config).
  def normalize_options(options)
    options.map do |opt|
      if opt.is_a?(Hash)
        { "label" => opt["label"].to_s, "value" => opt["value"].to_s }
      else
        { "label" => opt.to_s, "value" => opt.to_s }
      end
    end
  end

  def normalize_property_type(html_type)
    HTML_TYPE_TO_PROPERTY_TYPE[html_type] || "string"
  end
end
