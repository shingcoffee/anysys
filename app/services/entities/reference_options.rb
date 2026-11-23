# frozen_string_literal: true

module Entities
  # The choices of a reference dropdown: [label, id string] pairs for the
  # target entity's records in one tenant, labelled by the display field as
  # that tenant's definition has it. A configuration that cannot produce
  # labels lists nothing; nothing here raises on bad configuration.
  class ReferenceOptions
    DEFAULT_LIMIT = 200
    ID = /\A\d+\z/
    SLUG = /\A\w+\z/

    def self.call(...) = new(...).options

    def initialize(entity_id:, label_field:, customer_id:, audience:, viewer: nil, limit: DEFAULT_LIMIT)
      @entity_id = entity_id.to_s
      @label_field = label_field.to_s
      @customer_id = customer_id
      @audience = audience
      @viewer = viewer
      @limit = limit.to_i
    end

    # The tenant's own or a shared entity that is neither trashed nor a bridge.
    def target
      return @target if defined?(@target)

      @target = if @customer_id.present? && @entity_id.match?(ID)
        Entity.where(customer_id: [@customer_id, nil]).non_bridge.find_by(id: @entity_id)
      end
    end

    # The display field exists for the tenant, can label a reference, and is
    # visible to the audience.
    def usable?
      attribute = label_attribute
      ReferenceLabels.labelable?(attribute) && EntityAttributeAudience.visible_to?(attribute, @audience)
    end

    def options
      return [] unless usable?

      pairs = entries.order(Arel.sql("LOWER(CAST(#{label_sql} AS TEXT))"), :id)
                     .limit(@limit)
                     .pluck(:id, Arel.sql(label_sql))
                     .map { |id, raw| [ReferenceLabels.text(raw, id), id.to_s] }
      ReferenceLabels.disambiguate(pairs)
    rescue ActiveRecord::StatementInvalid
      []
    end

    # Whether a record other than `except_id` already shows this label.
    def label_taken?(label, except_id:)
      text = label.to_s.strip
      return false if text.empty? || !usable?

      entries.where.not(id: except_id).where("TRIM(CAST(#{label_sql} AS TEXT)) = ?", text).exists?
    end

    # { id string => raw label } for the given ids that are records of the
    # target in this tenant, or nil when the display field can't label them
    # for the audience.
    def labels(ids)
      return unless usable?

      wanted = Array(ids).map(&:to_s).select { |id| id.match?(ID) }.uniq
      return {} if wanted.empty?

      entries.where(id: wanted).pluck(:id, Arel.sql(label_sql)).to_h { |id, raw| [id.to_s, raw] }
    rescue ActiveRecord::StatementInvalid
      {}
    end

    private

    def entries
      return EntityEntry.none unless target

      People::Ownership.scope(target, viewer: @viewer, audience: @audience, customer_id: @customer_id)
    end

    # Only reached through #usable?, so the slug matched a schema attribute
    # and the SLUG format; quoting keeps the JSON path a literal regardless.
    def label_sql
      "json_extract(entity_entries.data, #{EntityEntry.connection.quote("$.\"#{@label_field}\"")})"
    end

    def label_attribute
      return @label_attribute if defined?(@label_attribute)

      @label_attribute = (find_label_attribute if target && @label_field.match?(SLUG))
    end

    def find_label_attribute
      payload = target.resolved_current_version(@customer_id)&.content&.payload
      schema = payload.present? ? Array(JSON.parse(payload)["property_schema"]) : []
      schema.find { |attribute| attribute.is_a?(Hash) && attribute["name_slug"].to_s == @label_field }
    rescue JSON::ParserError
      nil
    end
  end
end
