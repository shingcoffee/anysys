# frozen_string_literal: true

# Routes nested form params to structured groups based on page field configuration.
#
# Expects nested params from the form submission:
#   { "entity" => { "grade" => "A" },
#     "assoc" => { "assoc_student_course" => { "course" => "12", "score" => "95" } } }
#
# Returns structured result:
#   { primary: { base_models: {}, entity: {...} },
#     associations: [{ entity_id: 100, entity_name: "course",
#                      bridge: { entity_id: 200, entity_name: "assoc_student_course", params: {...} } }] }
#
# @example
#   FormParamsRouter.call(page, params)
#
class FormParamsRouter
  def self.call(page, raw_params)
    new(page).call(raw_params)
  end

  def initialize(page)
    @page = page
    @config = page.configuration_json || {}
  end

  def call(raw_params)
    {
      primary: build_primary(raw_params),
      associations: build_associations(raw_params)
    }
  end

  private

  def build_primary(raw_params)
    {
      base_models: {},
      entity: (raw_params["entity"] || {}).to_h
    }
  end

  def build_associations(raw_params)
    assoc_params = raw_params["assoc"] || {}
    return [] if assoc_params.empty?

    association_meta.filter_map do |meta|
      section_key = meta[:section_key]
      section_params = assoc_params[section_key]
      next unless section_params.is_a?(Hash)

      {
        entity_id: meta[:entity_id],
        entity_name: meta[:entity_name],
        bridge: {
          entity_id: meta[:bridge_entity_id],
          entity_name: meta[:bridge_entity_name],
          params: section_params.to_h
        }
      }
    end
  end

  # Build association metadata from page fields.
  # Groups bridge fields by source_section to identify distinct associations.
  def association_meta
    @association_meta ||= begin
      all_fields = (@config["pages"] || []).flat_map { |p| p["fields"] || [] }
      bridge_fields = all_fields.select { |f| f["source"] == "bridge" }

      sections = bridge_fields.group_by { |f| f["source_section"] }

      entity = find_bound_entity
      associations = entity&.associations_json || []

      sections.filter_map do |section_name, _fields|
        assoc = associations.find do |a|
          (a["bridge_entity_id"].present? && a["bridge_entity_id"].to_s == section_name.to_s) ||
            find_bridge_entity_name(a) == section_name
        end
        next unless assoc

        target_entity = Entity.find_by(id: assoc["target_entity_id"])
        bridge_entity = Entity.find_by(id: assoc["bridge_entity_id"])

        {
          section_key: slugify(section_name),
          entity_name: target_entity&.name || assoc["target_entity_name"],
          entity_id: target_entity&.id,
          bridge_entity_name: bridge_entity&.name || section_name,
          bridge_entity_id: bridge_entity&.id
        }
      end
    end
  end

  def find_bound_entity
    entity_id = @config.dig("metadata", "entity_id")
    Entity.find_by(id: entity_id) if entity_id
  end

  def find_bridge_entity_name(assoc)
    if assoc["bridge_entity_id"]
      Entity.find_by(id: assoc["bridge_entity_id"])&.name
    else
      assoc["bridge_entity_name"]
    end
  end

  def slugify(name)
    SectionSlug.for(name)
  end
end
