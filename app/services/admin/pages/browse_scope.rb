# frozen_string_literal: true

module Admin
  module Pages
    # The same effective binding powers both browse lists and form counts.
    # Explicit customer ids keep query results independent of ambient Current.
    # A page is bound when its effective metadata names one of the customer's
    # browsable (non-bridge) entities; every other page is unbound.
    class BrowseScope
      BINDING_SQL = "NULLIF(TRIM(CAST(json_extract(COALESCE(browse_override_content.payload, browse_default_content.payload), '$.metadata.entity_id') AS TEXT)), '')"
      ENTITY_ID_SQL = "CASE WHEN #{BINDING_SQL} NOT GLOB '*[^0-9]*' THEN CAST(#{BINDING_SQL} AS INTEGER) ELSE NULL END"

      # `entity_ids` keeps pages bound to those entities, `unbound` adds the
      # unbound pages; with neither, every accessible page is returned.
      def self.call(customer_id:, entity_ids: nil, unbound: false)
        new(customer_id: customer_id).call(entity_ids: entity_ids, unbound: unbound)
      end

      def initialize(customer_id:)
        @customer_id = customer_id
      end

      def call(entity_ids: nil, unbound: false)
        scope = all
        return scope if entity_ids.nil? && !unbound

        ids = Array(entity_ids).map(&:to_i).select { |id| known_entity_ids.include?(id) }
        conditions = []
        conditions << Page.sanitize_sql_array(["(#{ENTITY_ID_SQL}) IN (?)", ids]) if ids.any?
        conditions << unbound_condition if unbound
        return scope.none if conditions.empty?

        scope.where(conditions.map { |sql| "(#{sql})" }.join(" OR "))
      end

      def all
        cid = Page.connection.quote(@customer_id)
        Page.where(customer_id: @customer_id).or(Page.shared).joins(<<~SQL.squish)
          LEFT JOIN page_versions AS browse_default_version ON browse_default_version.id = pages.current_version_id
          LEFT JOIN page_configuration_contents AS browse_default_content ON browse_default_content.id = browse_default_version.content_id
          LEFT JOIN page_customer_heads AS browse_override_head ON browse_override_head.page_id = pages.id
            AND browse_override_head.customer_id = #{cid} AND pages.customer_id IS NULL
          LEFT JOIN page_versions AS browse_override_version ON browse_override_version.id = browse_override_head.current_version_id
          LEFT JOIN page_configuration_contents AS browse_override_content ON browse_override_content.id = browse_override_version.content_id
        SQL
      end

      def known_entity_ids
        @known_entity_ids ||= Entity.where(customer_id: @customer_id).or(Entity.shared).non_bridge.ids.to_set
      end

      private

      def unbound_condition
        Page.sanitize_sql_array(
          ["(#{ENTITY_ID_SQL}) IS NULL OR (#{ENTITY_ID_SQL}) NOT IN (?)", known_entity_ids.to_a.presence || [0]]
        )
      end
    end
  end
end
