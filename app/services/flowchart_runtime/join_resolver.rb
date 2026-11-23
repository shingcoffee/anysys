# frozen_string_literal: true

module FlowchartRuntime
  class JoinResolver
    class Error < StandardError; end

    attr_reader :source_entity, :target_entity, :bridge_entity, :customer_id

    def initialize(source_entity:, target_entity:, bridge_entity:, customer_id:)
      raise Error, "source entity is required" if source_entity.nil?
      raise Error, "target entity is required" if target_entity.nil?
      raise Error, "bridge entity is required" if bridge_entity.nil?
      raise Error, "customer id is required" if customer_id.nil?

      @source_entity = source_entity
      @target_entity = target_entity
      @bridge_entity = bridge_entity
      @customer_id = customer_id
    end

    # Apply SQL-level JOIN through bridge entity to an existing scope.
    def apply_sql_join(base_scope, join_type: "inner")
      source_slug = reference_slug_for(source_entity)
      target_slug = reference_slug_for(target_entity)
      join_keyword = join_type == "left" ? "LEFT JOIN" : "INNER JOIN"

      join_sql = <<~SQL.squish
        #{join_keyword} entity_entries AS bridge_entries
          ON bridge_entries.entity_id = #{bridge_entity.id.to_i}
          AND bridge_entries.customer_id = #{customer_id.to_i}
          AND json_extract(bridge_entries.data, '$.#{source_slug}') = CAST(entity_entries.id AS TEXT)
        #{join_keyword} entity_entries AS target_entries
          ON target_entries.entity_id = #{target_entity.id.to_i}
          AND CAST(target_entries.id AS TEXT) = json_extract(bridge_entries.data, '$.#{target_slug}')
      SQL

      base_scope.joins(join_sql)
    end

    # Application-level fallback: resolve target entry IDs linked to a source entry.
    def resolve_related_ids(source_entry_id)
      source_slug = reference_slug_for(source_entity)
      target_slug = reference_slug_for(target_entity)

      EntityEntry
        .where(entity_id: bridge_entity.id, customer_id: customer_id)
        .where("json_extract(data, '$.#{source_slug}') = ?", source_entry_id.to_s)
        .pluck(Arel.sql("json_extract(data, '$.#{target_slug}')"))
        .compact
    end

    # Auto-detect bridge entity linking source to target.
    def self.detect_bridge(source_entity, target_entity)
      associations = source_entity.associations_list
      assoc = associations.find { |a| a["target_entity_id"].to_i == target_entity.id }
      return nil unless assoc

      bridge_id = assoc["bridge_entity_id"]
      return nil unless bridge_id

      Entity.find_by(id: bridge_id)
    end

    OPERATIONS = %w[find create update list count].freeze

    # Find, create, update, list, or count related target entries for the bound association.
    def self.related(ctx, association:, operation:, source:, conditions: nil, assignments: {}, **listing)
      op = operation.to_s
      raise Error, "invalid operation" unless OPERATIONS.include?(op)

      from_association(ctx, association, source).public_send(
        op, ctx, source: source, conditions: conditions, assignments: assignments, **listing
      )
    rescue EntityResolver::Error, Entries::Error => error
      raise Error, error.message
    end

    # The links start from the record passed in, which need not be the page's.
    def self.from_association(ctx, association, source = nil)
      source_entity = source.is_a?(EntityEntry) ? source.entity : ctx && ctx[:bound_entity]
      raise Error, "source entity is required" unless source_entity
      raise Error, "association is required" if association.blank?

      target = EntityResolver.named(association, customer_id: ctx[:customer_id])
      bridge = detect_bridge(source_entity, target)
      raise Error, "bridge entity is required" unless bridge

      new(
        source_entity: source_entity,
        target_entity: target,
        bridge_entity: bridge,
        customer_id: ctx[:customer_id]
      )
    end
    private_class_method :from_association

    def source_reference_slug
      reference_slug_for(source_entity)
    end

    def target_reference_slug
      reference_slug_for(target_entity)
    end

    def find(ctx, source:, conditions: nil, order_by: nil, order_direction: "asc", **)
      relation = related_scope(ctx, source, conditions)
      return nil if relation.nil?

      Entries.apply_order(relation, order_by.presence || "id", order_direction).first
    end

    def list(ctx, source:, conditions: nil, limit: 100, order_by: nil, order_direction: "asc", **)
      relation = related_scope(ctx, source, conditions)
      return [] if relation.nil?

      relation = Entries.apply_order(relation, order_by.presence || "id", order_direction)
      relation = relation.limit(limit.to_i) if limit.to_i.positive?
      relation.to_a
    end

    def count(ctx, source:, conditions: nil, **)
      related_scope(ctx, source, conditions)&.count || 0
    end

    def create(ctx, source:, assignments: {}, **)
      raise Error, "source is required" unless source

      target_entry = Entries.scope_for(ctx, target_entity).new(
        customer_id: ctx[:customer_id], entity_id: target_entity.id
      )
      Entries.assign(target_entry, assignments.to_h, strict: true)
      return false unless Entries.save(ctx, target_entry)

      bridge_entry = Entries.scope_for(ctx, bridge_entity).new(
        customer_id: ctx[:customer_id], entity_id: bridge_entity.id
      )
      Entries.assign(
        bridge_entry,
        { source_reference_slug => source.id.to_s, target_reference_slug => target_entry.id.to_s },
        strict: true
      )
      return false unless Entries.save(ctx, bridge_entry)

      target_entry
    end

    def update(ctx, source:, conditions: nil, assignments: {}, **)
      entry = find(ctx, source: source, conditions: conditions)
      return nil unless entry

      Entries.assign(entry, assignments.to_h, strict: true)
      return false unless Entries.save(ctx, entry)

      entry
    end

    private

    def related_scope(ctx, source, conditions)
      raise Error, "source is required" unless source

      ids = resolve_related_ids(source.id)
      return nil if ids.empty?

      relation = Entries.scope_for(ctx, target_entity).where(id: ids)
      Entries.apply_conditions(relation, conditions, ctx)
    end

    def reference_slug_for(entity)
      schema = bridge_entity.respond_to?(:property_schema_json) ? Array(bridge_entity.property_schema_json) : []
      matched = schema.find do |attr|
        attr.is_a?(Hash) && attr["type"] == Entity::ENTITY_REFERENCE_TYPE && attr["entity_id"].to_s == entity.id.to_s
      end
      matched&.fetch("name_slug", nil).presence || EntityEntry.attribute_slug_for(entity.name)
    end
  end
end
