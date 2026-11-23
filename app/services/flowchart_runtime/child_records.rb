# frozen_string_literal: true

module FlowchartRuntime
  # The records of another entity whose reference field points at a loaded
  # record — an order's lines, a cart's items, a member's carts — found,
  # listed, counted or created in the run's tenant. A bridge's rows are
  # child records of either end, so a link's own values (a quantity) are
  # read and written here.
  module ChildRecords
    class Error < StandardError; end

    OPERATIONS = %w[find list count create].freeze

    module_function

    def call(ctx, operation:, entity:, source:, field: nil, conditions: nil, assignments: {},
             limit: 100, order_by: nil, order_direction: "asc")
      op = operation.to_s
      raise Error, "invalid operation" unless OPERATIONS.include?(op)

      child = EntityResolver.named(entity, customer_id: ctx[:customer_id])
      source = parent_record(ctx, child, field, source)
      slug = reference_slug(child, source.entity, field)
      return create(ctx, child, slug, source, assignments) if op == "create"

      relation = Entries.apply_conditions(pointing_at(ctx, child, slug, source), conditions, ctx)
      return relation.count if op == "count"

      relation = Entries.apply_order(relation, order_by.presence || "id", order_direction)
      op == "find" ? relation.first : relation.limit([limit.to_i, 1].max).to_a
    rescue EntityResolver::Error, Entries::Error => error
      raise Error, error.message
    end

    # A loaded record, or the id a reference field holds (an order's member):
    # +field+ then says which entity the id is a record of.
    def parent_record(ctx, child, field, source)
      return source if source.is_a?(EntityEntry) && source.persisted?

      id = source.to_s.strip
      target = field.to_s.strip.present? && id.match?(/\A[1-9]\d*\z/) && Entries.reference_target(child, field.to_s.strip)
      record = target && Entries.scope_for(ctx, target).find_by(id: id)
      raise Error, "record is required" unless record

      record
    end

    # +field+ when given; otherwise the child's only reference to +parent+.
    def reference_slug(child, parent, field)
      if field.to_s.strip.present?
        slug = field.to_s.strip
        target = Entries.reference_target(child, slug)
        raise Error, "#{slug} is not a reference field of #{child.name}" unless target
        raise Error, "#{slug} on #{child.name} does not point at #{parent.name}" unless target.id == parent.id

        return slug
      end

      slugs = reference_slugs(child, parent)
      raise Error, "#{child.name} has no reference field pointing at #{parent.name}" if slugs.empty?
      raise Error, "#{child.name} has several reference fields pointing at #{parent.name}; name one" if slugs.size > 1

      slugs.first
    end

    def reference_slugs(child, parent)
      Array(child.try(:property_schema_json)).filter_map do |attribute|
        next unless Entries.reference_target_id(attribute).to_s == parent.id.to_s

        attribute["name_slug"].to_s.presence
      end
    end

    # A reference holds one record id, or a list of them; either may be
    # stored as a string or a number.
    def pointing_at(ctx, child, slug, source)
      safe = JsonPathValidator.safe_json_path!(slug)
      Entries.scope_for(ctx, child).where(
        "EXISTS (SELECT 1 FROM json_each(entity_entries.data, '$.#{safe}') AS ref WHERE CAST(ref.value AS TEXT) = ?)",
        source.id.to_s
      )
    end

    # The new row counts towards the record's totals, which are read again.
    def create(ctx, child, slug, source, assignments)
      entry = Entries.scope_for(ctx, child).new(customer_id: ctx[:customer_id], entity_id: child.id)
      Entries.assign(entry, assignments.to_h.transform_keys(&:to_s).merge(slug => source.id.to_s), strict: true)
      return false unless Entries.save(ctx, entry)

      source.reset_derived_values!
      entry
    end

    private_class_method :parent_record, :reference_slug, :reference_slugs, :pointing_at, :create
  end
end
