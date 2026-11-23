# frozen_string_literal: true

# Current
#
# Thread-safe storage for request-scoped attributes using Rails' ActiveSupport::CurrentAttributes.
# This is the core of our multi-tenant architecture, providing tenant isolation across the application.
#
# Usage:
#   # Set the current tenant (typically in a before_action)
#   Current.customer = Customer.find(params[:customer_id])
#
#   # Access current tenant anywhere in the request lifecycle
#   Current.customer          # => #<Customer id: 12345678, name: "Acme Corp">
#   Current.customer_id       # => 12345678
#   Current.customer?         # => true
#
#   # In models with tenant scoping
#   Flowchart.for_current_customer  # => scoped to Current.customer
#
# Thread Safety:
#   CurrentAttributes automatically resets between requests and is thread-safe.
#   Each request gets its own isolated copy of these attributes.
#
# @see https://api.rubyonrails.org/classes/ActiveSupport/CurrentAttributes.html
#
class Current < ActiveSupport::CurrentAttributes
  # The current tenant (customer) for this request
  attribute :customer

  # Optional: track request metadata for logging/auditing
  attribute :request_id
  attribute :user_agent
  attribute :ip_address
  attribute :user

  # Platform owner context tracking
  attribute :platform_owner_context
  attribute :original_customer
  attribute :acting_as_customer

  # Cached AccessPoints::Catalog for the request lifecycle (admin UI only)
  attribute :access_points_catalog

  # Immutable tenant-specific public-link identities, installed only around
  # public rendering/submission and restored afterwards (never a routing cache).
  attribute :page_shortcuts_lookup

  # True when the current request is under Shared Resources
  # (/admin/maintenance/platform/{constants,entities,flowcharts,pages}).
  attribute :shared_resources_mode

  # ==========================================================================
  # Convenience Methods
  # ==========================================================================

  # Returns the current customer's ID
  #
  # @return [Integer, nil] the customer ID or nil if no customer is set
  def customer_id
    customer&.id
  end

  # Check if a customer is currently set
  #
  # @return [Boolean] true if a customer is set
  def customer?
    customer.present?
  end

  # Check if currently in platform owner context
  #
  # @return [Boolean] true if acting as another customer
  def platform_owner_context?
    platform_owner_context == true
  end

  # Set customer by ID (convenience method)
  #
  # @param id [Integer, String] the customer ID
  # @return [Customer, nil] the found customer or nil
  def customer_id=(id)
    self.customer = Customer.find_by(id: id) if id.present?
  end

  # ==========================================================================
  # Tenant Context Helpers
  # ==========================================================================

  # Execute a block within the context of a specific customer
  #
  # @param customer [Customer] the customer to set as current
  # @yield the block to execute within the customer context
  # @return the result of the block
  #
  # @example
  #   Current.with_customer(customer) do
  #     Flowchart.for_current_customer.count
  #   end
  #
  def self.with_customer(customer, &block)
    original_customer = self.customer
    self.customer = customer
    yield
  ensure
    self.customer = original_customer
  end

  # ==========================================================================
  # Callbacks
  # ==========================================================================

  # Reset callback - called automatically between requests
  # Can be used for cleanup or logging
  resets do
    # Optional: Log tenant context reset for debugging
    # Rails.logger.debug "[Current] Reset tenant context"
  end
end
