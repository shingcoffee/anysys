# frozen_string_literal: true

# RouteAuthorization
#
# Single, declarative protection layer for tenant-scoped admin and
# member URLs. Per AGENTS.md, every URL falls into one of three
# categories:
#
#   a) admin       — /:cid/admin/...        (requires admin/owner)
#   b) member — /:cid/member/...  (requires member)
#   c) public      — anything else          (no auth)
#
# This concern is responsible for categories (a) and (b). It runs as a
# global before_action and is the *only* place these prefixes are
# enforced — individual controllers MUST NOT repeat
# `before_action :authenticate_user!` or role checks for paths that fall
# under these prefixes. New URLs added later automatically inherit the
# correct gate based on path, removing the failure mode where a
# developer forgets to add a filter to a new admin controller.
#
# Pipeline (only when the path matches a protected prefix):
#
#   1. authenticate_user!      — anonymous users get the standard Devise
#                                redirect to /auth/sign_in (or 401 JSON).
#   2. enforce_route_role!     — RBAC gate keyed off path:
#                                  /admin/maintenance/platform/* → platform_owner
#                                  /admin/maintenance/flowcharts* → platform_owner
#                                  OwnerOnlySurfaces controllers  → platform_owner
#                                    (flowcharts, domains)
#                                  /admin/*                       → admin or owner
#                                  /member/*                 → member
#                                  /member/* (opt-in exception) → same-tenant
#                                    admin/owner may GET/HEAD when the controller
#                                    calls allow_admin_member_preview!. Writes
#                                    (POST/PATCH/PUT/DELETE) remain member-only.
#                                    Cross-tenant access is still blocked by
#                                    TenantContext; CanCan authorize_route! runs.
#   3. authorize_route!        — CanCan check against
#                                  :"route_<controller_path>" with the
#                                  HTTP-verb-derived action.
#
# AccessDenied responses are tenant-aware: HTML denials redirect inside
# the user's own tenant rather than dropping them on the marketing root.
module RouteAuthorization
  extend ActiveSupport::Concern

  # A namespace segment ends at "/", at Rails' optional "(.:format)" suffix, or
  # at end-of-path. The boundary must include "." — `admin_root` and
  # `member_dashboard` are routed as `/:customer_id/admin(.:format)` and
  # `/:customer_id/member(.:format)`, so a `/|\z` boundary left
  # `/12345678/admin.json` uncategorised and every filter below is declared
  # `if: :route_protection_required?`. That made the two namespace-root routes
  # reachable with no authentication, no role gate, and no CanCan check.
  SEGMENT_END              = "(?:[/.]|\\z)"
  ADMIN_PATH_PATTERN       = %r{\A/\d{8}/admin#{SEGMENT_END}}
  MEMBER_PATH_PATTERN      = %r{\A/\d{8}/member#{SEGMENT_END}}
  PLATFORM_NAMESPACE       = "admin/maintenance/platform/"
  PLATFORM_PATH_PATTERN    = %r{/admin/maintenance/platform#{SEGMENT_END}}
  FLOWCHART_PATH_PATTERN   = %r{/admin/maintenance/flowcharts#{SEGMENT_END}}

  VERB_TO_ACTION = {
    "GET"    => :read,
    "HEAD"   => :read,
    "POST"   => :create,
    "PATCH"  => :update,
    "PUT"    => :update,
    "DELETE" => :destroy
  }.freeze

  included do
    rescue_from CanCan::AccessDenied, with: :handle_access_denied

    # Order matters: authenticate first (redirects anonymous users to
    # sign-in), then enforce role, then CanCan. Each filter only runs
    # for protected prefixes — public URLs see none of them.
    before_action :authenticate_user!,    if: :route_protection_required?
    before_action :enforce_route_role!,   if: :route_protection_required?
    before_action :enforce_platform_path_identity!, if: -> { route_protection_required? && platform_namespace? }
    before_action :authorize_route!,      if: :route_protection_required?

    # Per-controller opt-in (see .allow_admin_member_preview!) letting
    # same-tenant admins/owners GET a member-namespace controller.
    class_attribute :admin_member_preview_allowed, default: false, instance_writer: false
  end

  class_methods do
    # Opt-in for member-namespace controllers that admins may open directly
    # (read-only preview — GET/HEAD only; writes remain member-only).
    # Cross-tenant access is still rejected by TenantContext, and CanCan's
    # authorize_route! continues to run.
    def allow_admin_member_preview!
      self.admin_member_preview_allowed = true
    end
  end

  private

  def route_protection_required?
    admin_path? || member_path?
  end

  # Categorise on the same string the router matched. `request.path` prepends
  # SCRIPT_NAME, so mounting the app under a sub-path (RAILS_RELATIVE_URL_ROOT
  # or a proxy setting SCRIPT_NAME) would keep routing intact while silently
  # un-matching every pattern here — a total bypass.
  def authorization_path
    request.path_info
  end

  def admin_path?
    authorization_path.match?(ADMIN_PATH_PATTERN)
  end

  def member_path?
    authorization_path.match?(MEMBER_PATH_PATTERN)
  end

  # Shared Resources remounts tenant maintenance controllers under
  # /admin/maintenance/platform/, so `controller_path` stays
  # `admin/maintenance/constants` (etc.). Gate on the URL as well.
  def platform_namespace?
    controller_path.start_with?(PLATFORM_NAMESPACE) ||
      authorization_path.match?(PLATFORM_PATH_PATTERN)
  end

  # Mirror platform_namespace?: gate on the controller as well as the URL.
  # Tenant admins have CanCan :manage, :all, so a flowchart (or domain)
  # controller remounted off its path would otherwise only be owner-gated by
  # the path regex.
  def owner_only_namespace?
    OwnerOnlySurfaces.controller?(controller_path) ||
      authorization_path.match?(FLOWCHART_PATH_PATTERN)
  end

  # Path-driven role gate. Runs after `authenticate_user!`, so
  # `current_user` is guaranteed present here.
  def enforce_route_role!
    if platform_namespace? || owner_only_namespace?
      return if current_user.platform_owner?
      raise CanCan::AccessDenied, t("common.errors.authorization.platform_owner_required")
    end

    if admin_path?
      return if current_user.admin_or_owner?
      raise CanCan::AccessDenied, t("common.errors.authorization.admin_required")
    end

    if member_path?
      return if current_user.member?
      return if admin_member_preview_allowed && (request.get? || request.head?) &&
                current_user.admin_or_owner? && current_user.customer_id == current_customer_id

      raise CanCan::AccessDenied, t("common.errors.authorization.member_required")
    end
  end

  def authorize_route!
    authorize! verb_action, route_subject
  end

    # Platform tools are authorized from the outer PATH_INFO customer id.
    # A nested record id, query string, or request body must not replace it.
  def enforce_platform_path_identity!
    head :not_found unless tenant_customer_id_from_path == Authentication::User::PLATFORM_CUSTOMER_ID.to_s
  end

  def verb_action
    VERB_TO_ACTION.fetch(request.method, :read)
  end

  def route_subject
    :"route_#{controller_path.tr('/', '_')}"
  end

  # Tenant-aware response. We avoid sending the user back to the marketing
  # root_path (which drops their tenant context) when we can keep them on
  # their own customer's dashboard.
  def handle_access_denied(exception)
    message = exception.message.presence || t("common.flash.access_denied")

    respond_to do |format|
      format.html { deny_html(message) }
      format.json { render json: { error: "access_denied" }, status: :forbidden }
      format.any  { head :forbidden }
    end
  end

  # Send the user to a surface they can actually open. This previously
  # returned "/#{cid}", which has no route at all, so every HTML denial landed
  # the user on a routing error instead of their own dashboard.
  #
  # If the denial happened *at* that surface the redirect would bounce forever
  # (a user carrying no role row resolves to the member surface, which the
  # role gate then denies), so answer terminally instead.
  def deny_html(message)
    target = Authentication::LandingPath.for(current_user)

    if target == authorization_path
      render plain: message, status: :forbidden
    else
      redirect_to target, alert: message
    end
  end
end
