# frozen_string_literal: true

module Entities
  module ComputedOptions
    NUMERIC_HTML_TYPES = ComputedCompiler::NUMERIC_HTML_TYPES

    def self.call(entity:, customer_id:)
      return [] if entity.nil? || entity.new_record? || entity.bridge_entity?

      forward_options(entity, customer_id) + reverse_options(entity, customer_id)
    end

    def self.forward_options(entity, customer_id)
      entity.associations_list.filter_map do |assoc|
        bridge_id = assoc["bridge_entity_id"]
        next if bridge_id.blank?

        bridge = find_bridge(customer_id, bridge_id)
        next unless bridge

        target = Entity.where(customer_id: customer_id).find_by(id: assoc["target_entity_id"].to_i)
        related_label = target&.display_label.presence ||
                        assoc["target_entity_name"].presence ||
                        assoc["target_entity_display_label"].presence ||
                        ""

        option_hash(bridge, bridge_role: "source", related_entity_label: related_label)
      end
    end
    private_class_method :forward_options

    def self.reverse_options(entity, customer_id)
      Entity.where(customer_id: customer_id, category: :bridge).filter_map do |bridge|
        schema = Array(bridge.property_schema_json)
        target_ref = schema[1]
        next unless target_ref.is_a?(Hash) && target_ref["entity_id"].to_s == entity.id.to_s

        source_ref = schema[0]
        related_label = related_label_from_ref(source_ref, customer_id)
        option_hash(bridge, bridge_role: "target", related_entity_label: related_label)
      end
    end
    private_class_method :reverse_options

    def self.find_bridge(customer_id, bridge_id)
      Entity.where(customer_id: customer_id, category: :bridge).find_by(id: bridge_id.to_i)
    end
    private_class_method :find_bridge

    def self.related_label_from_ref(ref, customer_id)
      return "" unless ref.is_a?(Hash)

      source = Entity.where(customer_id: customer_id).find_by(id: ref["entity_id"].to_i)
      source&.display_label.presence || ref["name"].to_s
    end
    private_class_method :related_label_from_ref

    def self.option_hash(bridge, bridge_role:, related_entity_label:)
      {
        "bridge_entity_id" => bridge.id,
        "bridge_role" => bridge_role,
        "related_entity_label" => related_entity_label.to_s,
        "bridge_label" => (bridge.display_label.presence || bridge.name).to_s,
        "attributes" => attributes_for(bridge)
      }
    end
    private_class_method :option_hash

    def self.attributes_for(bridge)
      Array(bridge.property_schema_json).drop(2).filter_map do |attr|
        next unless attr.is_a?(Hash)

        slug = attr["name_slug"].to_s
        next if slug.empty?

        {
          "slug" => slug,
          "label" => (attr["display_label"].presence || attr["name"].presence || slug).to_s,
          "numeric" => NUMERIC_HTML_TYPES.include?(attr["html_type"].to_s)
        }
      end
    end
    private_class_method :attributes_for
  end
end
