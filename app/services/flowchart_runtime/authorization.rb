# frozen_string_literal: true

module FlowchartRuntime
  # Role and CanCanCan checks for authorize steps. Reads ctx[:current_user]
  # when Load current user has written it, otherwise the verified session
  # principal. current_user_role is display metadata and never grants access.
  module Authorization
    class Error < StandardError; end

    RESERVED_ROLES = %w[owner admin member].freeze
    ABILITY_ACTION_RE = /\A[a-z_][a-z0-9_]*\z/i
    AUTH_TYPES = %w[role_check ability_check multi_role record_owner].freeze

    module_function

    def allowed?(ctx, user:, type:, role: "admin", roles: [], mode: "any_of",
                 action: "read", resource: nil)
      case type.to_s
      when "ability_check"
        ability_allowed?(ctx, user: user, action: action, resource: resource)
      when "multi_role"
        role_allowed?(ctx, user: user, roles: Array(roles), mode: mode)
      when "record_owner"
        record_owned?(ctx, user: user, record: resource)
      else
        role_allowed?(ctx, user: user, roles: [role], mode: "any_of")
      end
    end

    def role_allowed?(ctx, user:, roles:, mode: "any_of")
      wanted = Array(roles).map(&:to_s).select { |item| RESERVED_ROLES.include?(item) }
      return false if wanted.empty?

      actual = principal_roles(ctx, user)
      return false if actual.empty?

      if mode.to_s == "all_of"
        (wanted - actual).empty?
      else
        (wanted & actual).any?
      end
    end

    def ability_allowed?(ctx, user:, action:, resource:)
      raise Error, "invalid ability action" unless action.to_s.match?(ABILITY_ACTION_RE)

      principal = resolve_user(ctx, user)
      return false unless principal

      tenant_allowed = !resource.respond_to?(:customer_id) ||
        resource.customer_id.nil? ||
        principal.platform_owner? ||
        resource.customer_id == principal.customer_id

      tenant_allowed && Ability.new(principal).can?(action.to_sym, resource)
    end

    def resolve_user(ctx, user)
      return user if user.is_a?(::Authentication::User)

      Authentication.session(context: ctx && ctx[:authentication], customer_id: ctx && ctx[:customer_id])
    end

    def principal_roles(ctx, user)
      principal = resolve_user(ctx, user)
      principal ? principal.reserved_role_keys : []
    end

    # Member owns the record when user_id matches. Admin/owner still use
    # role_check; this is the per-record member gate, scoped to the tenant.
    def record_owned?(ctx, user:, record:)
      principal = resolve_user(ctx, user)
      return false unless principal
      return false if record.nil?

      if record.respond_to?(:customer_id) && record.customer_id.present?
        same_tenant = principal.platform_owner? ||
          record.customer_id.to_s == principal.customer_id.to_s
        return false unless same_tenant
      end

      owner_id = record_user_id(record)
      owner_id.present? && owner_id.to_s == principal.id.to_s
    end

    def record_user_id(record)
      if record.respond_to?(:user_id)
        record.user_id
      elsif record.is_a?(Hash)
        record[:user_id] || record["user_id"]
      end
    end
    private_class_method :record_user_id
  end
end
