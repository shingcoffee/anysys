# frozen_string_literal: true

# TenantContext
#
# Controller concern that sets up the tenant (customer) context for requests.
# Uses ActiveSupport::CurrentAttributes via the Current class to provide
# thread-safe, request-scoped tenant isolation.
#
# Usage:
#   class ApplicationController < ActionController::Base
#     include TenantContext
#   end
#
#   # Tenant is auto-extracted for any URL whose first segment is an
#   # 8-digit customer id (`/:cid/...`). Regular controllers do nothing —
#   # `current_customer`, `current_customer_id`, and `tenant_set?` are
#   # available out of the box.
#
#   # The dynamic catch-all controller bundles the customer_id inside
#   # `params[:path]` rather than a named segment, so it opts in:
#   class SomePathController < ApplicationController
#     set_tenant_from_path segment: 0
#   end
#
#   # Access current tenant anywhere
#   Current.customer     # => #<Customer id: 12345678>
#   Current.customer_id  # => 12345678
#
module TenantContext
  extend ActiveSupport::Concern

  # Tenant URL prefix: any path beginning with an 8-digit customer id.
  TENANT_PATH_PATTERN = %r{\A/(?<cid>\d{8})(/|\z)}

  included do
    # Store request metadata in Current for logging/auditing
    before_action :set_request_metadata

    # Auto-extract tenant context for every tenant-scoped URL
    # (`/<8-digit-customer-id>/...`). Removes the need for individual
    # controllers to declare `set_tenant_from_route_params` — a single
    # before_action covers admin, member, auth, public-form, and
    # any future tenant-scoped namespace.
    #
    # Specialized extractors (e.g. `set_tenant_from_path`) still run in
    # addition; they no-op if tenant is already set.
    before_action :auto_set_tenant_from_path

    # Helper method available in views
    helper_method :current_customer, :current_customer_id, :current_tenant_user, :tenant_set? if respond_to?(:helper_method)
  end

  class_methods do
    # Configure automatic tenant extraction from URL path segment.
    # Reserved for controllers where the customer_id is buried inside
    # `params[:path]` rather than a named route param.
    # Regular controllers do NOT need this — `auto_set_tenant_from_path`
    # in the included block already covers `/:customer_id/...` URLs.
    #
    # @param segment [Integer] the path segment index containing customer_id (0-based)
    # @param required [Boolean] whether to require tenant presence
    def set_tenant_from_path(segment: 0, required: true)
      before_action -> { extract_tenant_from_path(segment, required) }
    end
  end

  # ==========================================================================
  # Helper Methods
  # ==========================================================================

  # Returns the current customer (tenant)
  #
  # @return [Customer, nil] the current customer
  def current_customer
    Current.customer
  end

  # Returns the current customer ID
  #
  # @return [Integer, nil] the current customer ID
  def current_customer_id
    Current.customer_id
  end

  # Tenant-owned attribution (cards, member records) is stricter than actor
  # authorization: even a cross-tenant platform owner is not this tenant's user.
  def current_tenant_user
    user = current_user if respond_to?(:current_user)
    user if tenant_set? && user&.customer_id == current_customer_id
  end

  # Check if a tenant context is set
  #
  # @return [Boolean] true if tenant is set
  def tenant_set?
    Current.customer?
  end

  # ==========================================================================
  # Platform Owner Context
  # ==========================================================================

  # Clear platform owner context (return to own customer).
  # Tenant context is derived from the URL on every request, so this only
  # needs to drop the request-scoped Current attributes — there is no
  # session-stored context to wipe.
  def clear_platform_owner_context
    Current.platform_owner_context = false
    Current.original_customer = nil
    Current.acting_as_customer = nil
  end

  private

  # ==========================================================================
  # Tenant Extraction
  # ==========================================================================

  # Extract tenant from URL path segment
  #
  # @param segment [Integer] path segment index
  # @param required [Boolean] whether tenant is required
  def extract_tenant_from_path(segment, required)
    return if tenant_set?

    segments = tenant_path.split("/").reject(&:blank?)
    customer_id = segments[segment]

    set_current_tenant(customer_id, required)
  end

  # Auto-extract: any URL whose first segment is an 8-digit customer id
  # is a tenant URL, and the tenant is set without controllers having to
  # opt in. Required-ness is implicit — if the path matches the pattern,
  # the customer must exist; otherwise the request is rejected.
  def auto_set_tenant_from_path
    return if tenant_set?

    customer_id = tenant_customer_id_from_path
    set_current_tenant(customer_id, true) if customer_id
  end

  # Same string the router matched. `request.path` prepends SCRIPT_NAME, so a
  # mount prefix (RAILS_RELATIVE_URL_ROOT or a proxy) would make
  # TENANT_PATH_PATTERN miss, skip signed_in_other_tenant?, and leave
  # Current.customer unset while params[:customer_id] still carries the URL
  # tenant — a cross-tenant IDOR for any action that reads the param.
  def tenant_path
    request.path_info
  end

  def tenant_customer_id_from_path
    tenant_path.match(TENANT_PATH_PATTERN)&.[](:cid)
  end

  # Set the current tenant from customer_id
  #
  # @param customer_id [String, Integer] the customer ID
  # @param required [Boolean] whether tenant is required
  def set_current_tenant(customer_id, required)
    return unless customer_id.present?

    customer = Customer.find_by(id: customer_id)

    if customer && signed_in_other_tenant?(customer) && route_protection_required?
      return render_tenant_forbidden_error unless current_user.platform_owner?

      setup_platform_owner_context(customer)
    else
      Current.customer = customer
      clear_platform_owner_context
    end

    render_tenant_not_found_error(customer_id) if required && Current.customer.nil?
  end

  # Manually set tenant context (useful for testing or admin operations)
  #
  # @param customer [Customer] the customer to set as current
  def set_tenant(customer)
    Current.customer = customer
  end

  # ==========================================================================
  # Request Metadata
  # ==========================================================================

  # Store request metadata in Current for logging/auditing
  def set_request_metadata
    Current.request_id = request.request_id if request.respond_to?(:request_id)
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent
    Current.user = current_user if respond_to?(:current_user)
  end

  # ==========================================================================
  # Platform Owner Detection
  # ==========================================================================

  # Identify a foreign actor. Only protected admin/member routes reject that
  # actor; public surfaces remain open to signed-in visitors from any tenant.
  #
  # @param target_customer [Customer] the customer being accessed
  # @return [Boolean] true if a signed-in user is targeting a different tenant
  def signed_in_other_tenant?(target_customer)
    return false unless respond_to?(:current_user) && current_user.present?

    target_customer.id != current_user.customer_id
  end

  # Set up platform owner context attributes. Context is per-request and
  # derived from the URL — no session storage needed.
  #
  # @param target_customer [Customer] the customer being administered
  def setup_platform_owner_context(target_customer)
    Current.customer = target_customer
    Current.platform_owner_context = true
    Current.original_customer = current_user.customer
    Current.acting_as_customer = target_customer
  end

  # ==========================================================================
  # Error Rendering
  # ==========================================================================

  # Render tenant not found error
  #
  # @param customer_id [String, Integer] the customer ID that wasn't found
  def render_tenant_not_found_error(customer_id)
    respond_to do |format|
      format.json { render json: { error: t("common.flash.customer_not_found"), customer_id: customer_id }, status: :not_found }
      format.html { render plain: t("common.flash.customer_not_found"), status: :not_found }
      format.any { head :not_found }
    end
  end

  # Render forbidden cross-tenant error. Used when a signed-in user attempts
  # to access another customer's resources without platform-owner privileges.
  def render_tenant_forbidden_error
    respond_to do |format|
      format.json { render json: { error: "access_denied" }, status: :forbidden }
      # Back to the user's OWN tenant, on a surface their role can open — a
      # member bounced to /admin/dashboard would just be denied again.
      format.html do
        redirect_to Authentication::LandingPath.for(current_user),
                    alert: t("common.flash.access_denied")
      end
      format.any { head :forbidden }
    end
  end
end
