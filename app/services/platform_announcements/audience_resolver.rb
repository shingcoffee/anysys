# frozen_string_literal: true

module PlatformAnnouncements
  # Bound returned notices, not the global catalog before tenant eligibility.
  # Keyset batches keep memory bounded and avoid a query per announcement.
  class AudienceResolver
    BATCH_SIZE = 100

    def self.call(scope:, customer_id:, limit:, priority: false)
      new(scope: scope, customer_id: customer_id, limit: limit, priority: priority).call
    end

    def initialize(scope:, customer_id:, limit:, priority:)
      @scope = scope
      @customer_id = customer_id
      @limit = limit
      @priority = priority
    end

    def call
      return [] if @customer_id.blank?

      found = []
      cursor = nil
      loop do
        batch = ordered_scope
        batch = batch.where(after_cursor(cursor)) if cursor
        rows = batch.limit(BATCH_SIZE).to_a
        break if rows.empty?

        selected = rows.select(&:segmented?)
        matches = CustomerQuery.matching_keys(
          customer_id: @customer_id,
          rules_by_key: selected.to_h { |row| [row.id, row.target_rules] }
        ).to_set
        found.concat(rows.select { |row| row.all_customers? || matches.include?(row.id) }.first(@limit - found.size))
        break if found.size >= @limit || rows.size < BATCH_SIZE

        cursor = rows.last
      end
      found
    end

    private

    def table
      PlatformAnnouncement.arel_table
    end

    def rank
      Arel::Nodes::Case.new(table[:severity]).when("critical").then(0)
        .when("warning").then(1).when("info").then(2).else(3)
    end

    def ordered_scope
      order = [table[:created_at].desc, table[:id].desc]
      order.unshift(rank.asc) if @priority
      @scope.reorder(*order)
    end

    def after_cursor(cursor)
      older = table[:created_at].lt(cursor.created_at).or(
        table[:created_at].eq(cursor.created_at).and(table[:id].lt(cursor.id))
      )
      return older unless @priority

      value = { "critical" => 0, "warning" => 1, "info" => 2 }.fetch(cursor.severity, 3)
      rank.gt(value).or(rank.eq(value).and(older))
    end
  end
end
