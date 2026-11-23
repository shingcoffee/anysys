# frozen_string_literal: true

module People
  # Which rows of an entity each audience may reach.
  # Flowchart runtime never calls this: flowcharts must see every row.
  #
  # Kinds: a person entity; owned (one person reference names the owner);
  # private (person references, none the owner); nested (no person
  # reference, but rows hang off a member's records, as a cart's items hang
  # off the cart: a member reaches the rows whose every such parent they
  # reach); open (anyone in the tenant).
  module Ownership
    Owner = Data.define(:slug, :person_entity_id)
    Parent = Data.define(:slug, :entity_id)
    Descriptor = Data.define(:kind, :owner, :parents) do
      def initialize(kind:, owner:, parents: []) = super
    end
    NESTING_DEPTH = 3

    module_function

    def describe(entity, depth: 0)
      return Descriptor.new(kind: :person, owner: nil) if entity.person?

      references = person_references(entity)
      if references.any?
        owner = owner_from(references)
        return Descriptor.new(kind: owner ? :owned : :private, owner: owner)
      end

      parents = depth < NESTING_DEPTH ? owned_parents(entity, depth) : []
      Descriptor.new(kind: parents.empty? ? :open : :nested, owner: nil, parents: parents)
    end

    def kind(entity) = describe(entity).kind
    def owner_reference(entity) = describe(entity).owner

    def scope(entity, viewer:, audience:, customer_id:)
      rows = EntityEntry.where(customer_id: customer_id, entity_id: entity.id)
      return rows if audience.to_s == EntityAttributeAudience::ADMIN

      descriptor = describe(entity)
      return rows if descriptor.kind == :open && known_audience?(audience)
      return rows.none unless audience.to_s == EntityAttributeAudience::MEMBER && same_tenant?(viewer, customer_id)

      case descriptor.kind
      when :person then rows.where(user_id: viewer.id)
      when :owned then owned_rows(rows, descriptor.owner, viewer)
      when :nested then nested_rows(rows, descriptor.parents, viewer, customer_id)
      else rows.none
      end
    end

    def reachable_ids(entity, ids, viewer:, audience:, customer_id:)
      numeric = Array(ids).filter_map { |id| Integer(id, exception: false) }
      return [] if numeric.empty?

      scope(entity, viewer: viewer, audience: audience, customer_id: customer_id)
        .where(id: numeric)
        .pluck(:id)
        .map(&:to_s)
    end

    def person_entry_ids(user)
      return {} unless user

      entries = EntityEntry.where(customer_id: user.customer_id, user_id: user.id)
      return {} if entries.none?

      person_ids = person_entities(user.customer_id, entries.distinct.pluck(:entity_id)).pluck(:id)
      return {} if person_ids.empty?

      entries.where(entity_id: person_ids).each_with_object({}) do |entry, map|
        map[entry.entity_id.to_s] = entry.id
      end
    end

    def person_entry_id(user, person_entity_id)
      return if person_entity_id.blank?

      person_entry_ids(user)[person_entity_id.to_s]
    end

    def person_references(entity)
      candidates = Array(entity.property_schema_json).grep(Hash).filter_map do |attribute|
        target_id = reference_target_id(attribute)
        next if target_id.blank?

        { attribute: attribute, target_id: target_id }
      end
      return [] if candidates.empty?

      person_ids = person_entities(entity.customer_id, candidates.map { |row| row[:target_id] })
                    .pluck(:id)
                    .to_set { |id| id.to_s }

      candidates.select { |row| person_ids.include?(row[:target_id].to_s) }
    end

    def owner_from(references)
      flagged = references.select { |row| row.dig(:attribute, "owner") == true }
      chosen =
        if flagged.one?
          flagged.first
        elsif flagged.empty? && references.one?
          references.first
        end
      return unless chosen

      Owner.new(slug: chosen[:attribute]["name_slug"].to_s, person_entity_id: chosen[:target_id].to_i)
    end

    def owned_rows(rows, owner, viewer)
      return rows.none unless owner

      entry_id = person_entry_id(viewer, owner.person_entity_id)
      return rows.none unless entry_id

      slug = FlowchartRuntime::JsonPathValidator.safe_json_path!(owner.slug)
      rows.where("CAST(json_extract(data, '$.#{slug}') AS TEXT) = ?", entry_id.to_s)
    end

    # References to record types a member owns, directly or through their
    # own parents.
    def owned_parents(entity, depth)
      targets = Array(entity.property_schema_json).grep(Hash).filter_map do |attribute|
        target_id = reference_target_id(attribute)
        [attribute["name_slug"].to_s, target_id.to_s] if target_id.present? && attribute["name_slug"].present?
      end
      return [] if targets.empty?

      entities = Entity.unscoped.where(id: targets.map(&:last), customer_id: [entity.customer_id, nil].uniq).index_by { |row| row.id.to_s }
      targets.filter_map do |slug, target_id|
        target = entities[target_id]
        next unless target && target.id != entity.id && %i[owned nested].include?(describe(target, depth: depth + 1).kind)

        Parent.new(slug: slug, entity_id: target.id)
      end
    end

    def nested_rows(rows, parents, viewer, customer_id)
      parents.reduce(rows) do |kept, parent|
        target = Entity.unscoped.find_by(id: parent.entity_id)
        return rows.none unless target

        reachable = scope(target, viewer: viewer, audience: EntityAttributeAudience::MEMBER, customer_id: customer_id)
        slug = FlowchartRuntime::JsonPathValidator.safe_json_path!(parent.slug)
        kept.where("CAST(json_extract(entity_entries.data, '$.#{slug}') AS TEXT) IN " \
                   "(#{reachable.select('CAST(entity_entries.id AS TEXT)').to_sql})")
      end
    end

    def reference_target_id(attribute)
      if attribute["type"] == Entity::ENTITY_REFERENCE_TYPE
        attribute["entity_id"].presence
      elsif Entities::ReferenceLabels.reference?(attribute)
        attribute.dig("config", "entity_id").presence
      end
    end

    def person_entities(customer_id, ids)
      Entity.unscoped.where(
        id: ids,
        customer_id: [customer_id, nil].uniq,
        extended_model: EntityDefinitions::Capabilities::PERSON_MODEL
      )
    end

    def known_audience?(audience)
      EntityAttributeAudience::AUDIENCES.include?(audience.to_s)
    end

    def same_tenant?(viewer, customer_id)
      viewer && customer_id.present? && viewer.customer_id.to_s == customer_id.to_s
    end
    private_class_method :owner_from, :owned_rows, :owned_parents, :nested_rows, :reference_target_id,
                         :person_entities, :known_audience?, :same_tenant?
  end
end
