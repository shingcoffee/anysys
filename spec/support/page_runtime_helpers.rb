# frozen_string_literal: true

module PageRuntimeHelpers
  # UI generator examples still use real tenant bindings and declared schemas.
  # Boundary/security examples must supply their own schemas independently.
  def build_runtime_ui_page(config, customer:)
    fields = runtime_ui_fields(Array(config["pages"]).flat_map { |step| Array(step["fields"]) })
    schema = fields.uniq { |field| field.fetch("property_slug") }.map do |field|
      slug = field.fetch("property_slug")
      type = case field["property_type"]
             when "integer" then "Integer"
             when "number", "float" then "Float"
             when "boolean" then "Boolean"
             else "String"
             end
      { "name" => slug.humanize, "name_slug" => slug, "type" => type,
        "html_type" => field.fetch("html_type", "text") }.merge(field.slice("visibility"))
    end
    entity = create(:entity, customer: customer, property_schema: schema.to_json)
    build(:page, customer: customer, entity: entity, configuration: config.to_json)
  end

  private

  def runtime_ui_fields(fields)
    fields.flat_map do |field|
      if field["field_type"] == "columns"
        runtime_ui_fields(Array(field["columns"]).flat_map { |column| Array(column["fields"]) })
      elsif field["property_type"] == "layout" || %w[base_model bridge].include?(field["source"])
        []
      else
        [field]
      end
    end
  end
end
