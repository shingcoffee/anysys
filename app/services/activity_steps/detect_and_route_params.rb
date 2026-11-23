# frozen_string_literal: true

module ActivitySteps
  # Detects whether form params are multi-source (structured with entity/assoc keys)
  # and routes them into a uniform routed_params structure.
  #
  # Multi-source params (from page forms):
  #   { "entity" => { "grade" => "A" },
  #     "assoc" => { "assoc_student_course" => { "course" => "12" } } }
  #
  # Single-source params (flat params from simple forms):
  #   { "field1" => "value1", "field2" => "value2" }
  #
  # Always sets ctx[:routed_params] with uniform structure:
  #   { primary: { base_models: {}, entity: {...} },
  #     associations: [...] }
  #
  module DetectAndRouteParams
    module_function

    def call(ctx, **)
      return false if BaseModelInput.rejected?(ctx)
      params = ctx[:params] || {}

      ctx[:routed_params] = if multi_source?(params)
        route_multi_source(params, ctx[:bound_entity])
      else
        # Wrap flat params as entity-only for uniform handling
        { primary: { base_models: {}, entity: params }, associations: [] }
      end

      true
    end

    def multi_source?(params)
      params.is_a?(Hash) && (params.key?("base") || params.key?("entity") || params.key?("assoc"))
    end

    def route_multi_source(params, bound_entity)
      {
        primary: {
          # Intentionally empty: this executor persists EntityEntry records,
          # not the base model advertised by extension metadata.
          base_models: {},
          entity: extract_hash(params["entity"])
        },
        associations: build_associations(params["assoc"], bound_entity)
      }
    end

    def build_associations(assoc_params, bound_entity)
      return [] if assoc_params.blank? || bound_entity.nil?

      associations_meta = bound_entity.associations_list

      assoc_params.filter_map do |section_key, section_params|
        next unless section_params.is_a?(Hash)

        assoc = find_association(associations_meta, section_key)
        next unless assoc

        {
          entity_id:   assoc["target_entity_id"]   || assoc[:target_entity_id],
          entity_name: assoc["target_entity_name"]  || assoc[:target_entity_name],
          bridge: {
            entity_id:   assoc["bridge_entity_id"]   || assoc[:bridge_entity_id],
            entity_name: assoc["bridge_entity_name"] || assoc[:bridge_entity_name],
            params:      extract_hash(section_params)
          }
        }
      end
    end

    def find_association(associations_meta, section_key)
      associations_meta.find do |a|
        bridge_id = a["bridge_entity_id"] || a[:bridge_entity_id]
        next true if bridge_id.present? && bridge_id.to_s == section_key.to_s

        bridge_name = a["bridge_entity_name"] || a[:bridge_entity_name] || ""
        slugify(bridge_name) == section_key
      end
    end

    def slugify(name)
      SectionSlug.for(name)
    end

    def extract_hash(value)
      return {} unless value.is_a?(Hash) || (value.respond_to?(:to_h) && !value.is_a?(String))

      value.to_h
    end
  end
end
