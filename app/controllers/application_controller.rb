# frozen_string_literal: true

# ApplicationController
#
# Base controller for all application controllers.
# Provides tenant context and authorization functionality.
#
class ApplicationController < ActionController::Base
  include TenantContext
  include FeatureModules::HostIntegration
  include RouteAuthorization
  include SetLocale
  include Authentication::HandlesCredentialConflicts
  # Registers `before_action :enforce_mfa!`. Included last so the gate runs
  # after RouteAuthorization has authenticated and authorized the request.
  include Authentication::EnforcesMfa

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # ==========================================================================
  # Dashboard Layout Selection
  # ==========================================================================

  PLATFORM_OWNER_CONTROLLERS = %w[].freeze

  layout :dashboard_layout

  helper_method :current_dashboard_menu_item
  helper_method :auth_settings
  helper_method :shared_resources_mode?
  helper_method :can_destroy_definition?
  helper_method :can_copy_definition?

  # Class-level DSL — a controller declares which top-level dashboard tab it
  # belongs to with a single line: `dashboard_menu_item :modules`. Without an
  # explicit declaration the menu is inferred from the request path (see
  # MENU_ITEM_BY_PATH_PREFIX below).
  class_attribute :_dashboard_menu_item, instance_writer: false

  def self.dashboard_menu_item(item)
    self._dashboard_menu_item = item
  end

  # Check if current user has platform elevated access
  # This is true when a platform owner is acting in another customer's context
  #
  # @return [Boolean] true if elevated access is available
  def platform_elevated_access?
    Current.platform_owner_context? && current_user&.platform_owner?
  end

  # Get authentication settings for the current tenant
  # Memoized per-request since current_customer_id is stable per request
  #
  # @return [Authentication::Settings] immutable value object
  def auth_settings
    @auth_settings ||= Authentication::Settings.for(current_customer_id)
  end

  # Require platform elevated access for an action
  # Use for operations that only platform owners can perform in another customer's context
  def require_elevated_access!
    return if platform_elevated_access?

    respond_to do |format|
      format.html do
        redirect_to root_path, alert: t("common.flash.owner_required")
        return
      end
      format.json do
        render json: { error: "elevated_access_required" }, status: :forbidden
        return
      end
    end
  end

  def dashboard_layout
    # Turbo-Frame requests want only the matching frame's contents — skip the
    # entire dashboard chrome (sidebar, top bar, breadcrumbs, etc.) so the
    # response is just the rendered template. Turbo will still extract only
    # the frame from a layoutless response.
    return false if request.headers["Turbo-Frame"].present?
    return "application" unless Current.customer
    PLATFORM_OWNER_CONTROLLERS.include?(self.class.name) ? "application" : "dashboard"
  end

  # --------------------------------------------------------------------------
  # Menu-item inference from request path
  # --------------------------------------------------------------------------

  MENU_ITEM_BY_PATH_PREFIX = {
    "/assistant"    => :assistant,
    "/domains"      => :entities,
    "/entities"     => :entities,
    "/pages"        => :entities,
    "/modules"      => :modules,
    "/settings"     => :settings,
    "/maintenance"  => :maintenance
  }.freeze

  def current_dashboard_menu_item
    return _dashboard_menu_item if _dashboard_menu_item
    tr = tenant_relative_path
    if tr == "" || tr == "/"
      return request.path.match?(%r{/admin/?\z}) ? :assistant : :home
    end
    MENU_ITEM_BY_PATH_PREFIX.each do |prefix, item|
      return item if tr.start_with?(prefix)
    end
    :home
  end

  private

  def tenant_relative_path
    request.path.to_s.sub(%r{\A/\d{8}}, "").sub(%r{\A/admin(?=/|\z)}, "")
  end
end
