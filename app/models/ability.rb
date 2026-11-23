# frozen_string_literal: true

# Ability
#
# Translates persisted RolePermission rows into CanCanCan rules for a user.
#
# Tenant safety:
#   Instance-level grants for Entity/Page are intersected with the active
#   tenant (Current.customer_id). A grant whose target row belongs to a
#   different customer never produces a CanCan rule — even if the row exists
#   in the database (defense-in-depth against data drift, accidental cross-
#   tenant references, or bugs in the access-points seeder).
#
# Action safety:
#   Only actions in RolePermission::ACTIONS are translated. The model
#   already validates this; Ability re-checks at translation time so that
#   any legacy/malformed row that bypassed validation cannot inject a
#   custom action symbol.
#
class Ability
  include CanCan::Ability

  # Symbols used as cancan "subjects" for routes, modules, features, etc.
  # Build them through these helpers so the convention stays in one place.
  ROUTE_PREFIX    = "route_"
  MODULE_PREFIX   = "module_"
  FEATURE_PREFIX  = "feature_"
  PLATFORM_PREFIX = "platform_"

  # @param user [Authentication::User, nil]
  def initialize(user)
    # Regular users can only act inside their own tenant. Current.customer_id
    # is only authoritative when a platform owner is acting in another
    # tenant's context — but platform owners are owners and short-circuit to
    # :manage, :all below, so for instance-level data grants we always want
    # the user's own customer_id.
    @customer_id = user&.customer_id || Current.customer_id

    return if user.blank?

    if user.platform_owner?
      # Platform owner customer (81721200) — full access across every
      # tenant and every platform-scoped subject.
      can :manage, :all
      return
    end

    if user.has_reserved_role?(:admin)
      # Tenant admin — full access inside their own customer, but no
      # implicit access to platform-scoped subjects or owner-only routes
      # (flowcharts, domains). Those surfaces are also gated by
      # RouteAuthorization; these cannot rules keep `authorize_route!` honest
      # if a controller is remounted.
      can :manage, :all
      cannot :manage, platform_owner_subjects
      cannot :manage, Symbol do |subject|
        OwnerOnlySurfaces.route_subject?(subject)
      end
      return
    end

    if user.has_reserved_role?(:member)
      # Tenant member — implicit access to every member route within
      # their own customer. Member routes don't carry per-action
      # role_permission rows; the URL-prefix gate (RouteAuthorization)
      # plus per-record ownership checks (Member::BaseController#
      # authorize_owned!) provide the actual security. This rule lets the
      # CanCan layer pass for any /:cid/member/* request.
      can :manage, member_route_subjects
    end

    grants_for(user).each { |g| apply_grant(g) }
  end

  # Subjects that are reserved for the platform owner. Listed explicitly so
  # that adding a new platform-only subject is a deliberate change.
  def platform_owner_subjects
    [
      :"#{PLATFORM_PREFIX}customers",
      :"#{PLATFORM_PREFIX}announcements",
      :"#{PLATFORM_PREFIX}support_tickets",
      :"#{PLATFORM_PREFIX}module_settings",
      :"#{PLATFORM_PREFIX}industry_templates",
      :"#{PLATFORM_PREFIX}code_generators",
      :"#{PLATFORM_PREFIX}customer_context",
      :"#{PLATFORM_PREFIX}sms",
      :"#{PLATFORM_PREFIX}captcha",
      :"#{PLATFORM_PREFIX}ai_assistant"
    ]
  end

  # CanCan route subjects for /:cid/member/* paths. Adding a new
  # member controller means adding its symbol here so the member
  # role can pass the global authorize_route! filter; the actual
  # member-specific security lives in the URL-prefix gate and the
  # per-record ownership check.
  def member_route_subjects
    [
      :route_member_dashboards,
      :route_member_profiles,
      :route_member_securities,
      :route_member_mfa,
      :route_member_trusted_devices,
      :route_member_payments,
      :route_member_pages,
      :route_member_page_rows,
      :route_member_entity_entry_journeys,
      :route_member_surfaces,
      # Member payments self-service (card vault + subscriptions)
      :route_member_payments_payment_methods,
      :route_member_payments_subscriptions,
      :route_member_payments_subscription_cancellations
    ]
  end

  private

  attr_reader :customer_id

  def grants_for(user)
    RolePermissions::Operation::ResolveGrants.call(role_ids: user.role_ids)
  end

  def apply_grant(grant)
    action = normalize_action(grant.action)
    return unless action

    case grant.subject_type
    when "Route"
      return if OwnerOnlySurfaces.controller?(grant.subject_key)

      can action, route_subject(grant.subject_key)
    when "Module"      then can action, module_subject(grant.subject_key)
    when "FeaturePage" then can action, feature_subject(grant.subject_key)
    when "Platform"    then can action, platform_subject(grant.subject_key)
    when "EntityClass" then can action, Entity
    when "PageClass"   then can action, Page
    when "Entity"      then grant_instance(action, Entity, grant.subject_id)
    when "Page"        then grant_instance(action, Page,   grant.subject_id)
    end
  end

  def normalize_action(raw)
    return nil if raw.blank?
    return nil unless RolePermission::ACTIONS.include?(raw)

    raw == "manage" ? :manage : raw.to_sym
  end

  def route_subject(key)    = :"#{ROUTE_PREFIX}#{key.to_s.tr('/', '_')}"
  def module_subject(key)   = :"#{MODULE_PREFIX}#{key}"
  def feature_subject(key)  = :"#{FEATURE_PREFIX}#{key}"
  def platform_subject(key) = :"#{PLATFORM_PREFIX}#{key}"

  # Apply an instance-level grant only when it falls inside the current tenant.
  # Without this, a grant row pointing at another customer's record would be
  # honored purely on id-match. The customer_id constraint is included in the
  # CanCan condition hash so that any future `accessible_by` queries inherit
  # the same scope.
  def grant_instance(action, klass, id)
    return if id.blank?
    return if customer_id.blank?

    can action, klass, id: id, customer_id: customer_id
  end
end
