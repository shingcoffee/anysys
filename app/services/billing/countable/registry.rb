# frozen_string_literal: true

module Billing
  module Countable
    module Registry
      module_function

      def all
        @all ||= [
          ItemDefinition.new(key: "page", counter: ->(customer) { Page.for_customer(customer.id).count }),
          ItemDefinition.new(key: "entity", counter: ->(customer) { Entity.for_customer(customer.id).count }),
          ItemDefinition.new(key: "member", counter: ->(customer) {
            Authentication::User.unscoped.where(customer_id: customer.id).where.not(status: :trashed).joins(:roles)
              .where(roles: { customer_id: customer.id, key: "member" }).distinct.count
          })
        ].freeze
      end

      def keys = all.map(&:key)
      def find(key) = all.find { |definition| definition.key == key.to_s }
      def count_for(key, customer)
        definition = find(key)
        raise ArgumentError, "Unsupported billing counter" unless definition
        definition.count_for(customer)
      end
    end
  end
end
