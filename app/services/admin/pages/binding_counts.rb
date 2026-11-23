# frozen_string_literal: true

module Admin
  module Pages
    # Form counts per bound entity from one grouped query over BrowseScope, so
    # the counts always agree with the browse lists. Unbound pages (no entity,
    # a bridge entity, or one that no longer exists) are counted under nil.
    class BindingCounts
      Count = Data.define(:total, :live) do
        def self.empty = new(total: 0, live: 0)
        def +(other) = self.class.new(total: total + other.total, live: live + other.live)
      end

      def self.call(customer_id:)
        new(customer_id: customer_id).call
      end

      def initialize(customer_id:)
        @customer_id = customer_id
      end

      # { entity id => Count, nil => Count of unbound pages }; entities without
      # a page default to an empty Count.
      def call
        scope = BrowseScope.new(customer_id: @customer_id)
        known = scope.known_entity_ids
        raw = scope.all.group(Arel.sql(BrowseScope::ENTITY_ID_SQL), :launched).count

        raw.each_with_object(Hash.new(Count.empty)) do |((raw_id, launched), count), counts|
          entity_id = Integer(raw_id, exception: false)
          key = known.include?(entity_id) ? entity_id : nil
          live = ActiveModel::Type::Boolean.new.cast(launched) ? count : 0
          counts[key] += Count.new(total: count, live: live)
        end
      end
    end
  end
end
