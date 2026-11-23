# frozen_string_literal: true

# TenantScoped
#
# Provides automatic tenant (customer) scoping for ActiveRecord models.
# When included, the model will be automatically scoped to the current tenant
# using ActiveSupport::CurrentAttributes via the Current class.
#
# Usage:
#   class Flowchart < ApplicationRecord
#     include TenantScoped
#   end
#
#   # Automatic scoping via Current.customer
#   Current.customer = customer
#   Flowchart.all                    # => scoped to current customer
#   Flowchart.for_current_customer   # => explicit scoping
#   Flowchart.unscoped_by_tenant     # => all records (bypass tenant filter)
#
# Configuration:
#   class Flowchart < ApplicationRecord
#     include TenantScoped
#     tenant_scoped optional: true   # customer_id can be null
#   end
#
module TenantScoped
  extend ActiveSupport::Concern

  included do
    # Association to customer (tenant)
    # Optional to support shared resources (e.g., blueprint flowcharts)
    # Individual models should add their own validation if customer_id is required
    belongs_to :customer, optional: true

    # Callbacks to automatically set customer_id from Current.customer
    before_validation :set_customer_from_current, on: :create
  end

  class_methods do
    # Scope to the current customer from Current.customer
    #
    # @return [ActiveRecord::Relation] records for current customer
    #
    # @example
    #   Flowchart.for_current_customer.recent
    #
    def for_current_customer
      if Current.customer?
        where(customer_id: Current.customer_id)
      else
        none
      end
    end

    # Scope to a specific customer by ID
    #
    # @param customer_id [Integer] the customer ID to scope to
    # @return [ActiveRecord::Relation] records for specified customer
    #
    # @example
    #   Flowchart.for_customer(12345678).recent
    #
    def for_customer(customer_id)
      where(customer_id: customer_id)
    end

    # Bypass tenant scoping (use with caution!)
    #
    # @return [ActiveRecord::Relation] all records regardless of tenant
    #
    # @example
    #   # Admin-only operation
    #   Flowchart.unscoped_by_tenant.count
    #
    def unscoped_by_tenant
      unscope(where: :customer_id)
    end

    # Check if the model is tenant-scoped
    #
    # @return [Boolean] true if the model includes TenantScoped
    def tenant_scoped?
      true
    end
  end

  # Skip TenantScoped's create-time fill so a Shared Resource can persist
  # with customer_id NULL even when Current.customer is set (factories,
  # console). Request-path shared creates also skip via Current.shared_resources_mode.
  def skip_tenant_customer_assignment!
    @_skip_tenant_customer_assignment = true
  end

  private

  # Automatically set customer_id from Current.customer on create
  def set_customer_from_current
    return if skip_tenant_customer_assignment?
    return if Current.shared_resources_mode
    return if customer_id.present?
    return unless Current.customer?

    self.customer_id = Current.customer_id
  end

  def skip_tenant_customer_assignment?
    @_skip_tenant_customer_assignment == true
  end
end

