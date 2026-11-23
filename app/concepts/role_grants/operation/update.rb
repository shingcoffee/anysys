# frozen_string_literal: true

module RoleGrants
  module Operation
    class Update
      Result = Roles::Operation::Create::Result

      # Subject types that confer platform-wide (cross-tenant) authority — they
      # translate to `can :manage, :platform_*` in Ability, which is reserved
      # for the platform owner. A tenant admin editing a custom role must not be
      # able to mint one (it would be an inert-but-real CanCan grant today,
      # contained only by the path-level platform gate — defence-in-depth).
      #
      # Flowchart Route keys are the same class of owner-only subject: Ability
      # skips leftover rows, but a crafted grants PATCH must not persist them.
      OWNER_ONLY_SUBJECT_TYPES = %w[Platform].freeze

      def self.call(role:, added: [], removed: [], actor: nil)
        return Result.new(success?: false, model: role,
                          errors: { base: [I18n.t("auth.errors.role_grants_locked")] }) if role.locked_grants?

        ActiveRecord::Base.transaction do
          Array(added).each   { |g| add_grant!(role, g, actor: actor) }
          Array(removed).each { |g| remove_grant!(role, g) }
        end

        Result.new(success?: true, model: role, errors: nil)
      rescue PlatformGrantForbidden => e
        Result.new(success?: false, model: role, errors: { base: [e.message] })
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved, ActiveModel::ValidationError => e
        Rails.logger.warn("[role_grants] update failed: #{e.class}: #{e.message}")
        Result.new(success?: false, model: role, errors: { base: [I18n.t("auth.errors.role_grants_invalid")] })
      end

      # Raised when a non-owner attempts to add a platform-scoped grant.
      class PlatformGrantForbidden < StandardError
        def initialize(msg = I18n.t("auth.errors.platform_grant_forbidden"))
          super
        end
      end

      def self.add_grant!(role, attrs, actor: nil)
        subject_type = attrs[:subject_type] || attrs["subject_type"]
        subject_key  = attrs[:subject_key]  || attrs["subject_key"]
        subject_id   = attrs[:subject_id]   || attrs["subject_id"]
        action       = attrs[:action]       || attrs["action"]

        if owner_only_grant?(subject_type, subject_key) && !actor&.owner?
          raise PlatformGrantForbidden
        end

        # Instance grants must point at a row in the role's own tenant.
        # Without this check, a tenant admin could store a grant referencing
        # another customer's Entity/Page id; Ability#grant_instance would
        # then silently drop it, leaving an inert but misleading row.
        if RolePermission::INSTANCE_BASED_TYPES.include?(subject_type) && subject_id.present?
          klass = Object.const_get(subject_type)
          unless klass.where(id: subject_id, customer_id: role.customer_id).exists?
            raise ActiveRecord::RecordInvalid.new(role)
          end
        end

        role.role_permissions.create!(
          subject_type: subject_type,
          subject_key:  subject_key,
          subject_id:   subject_id,
          action:       action
        )
      end

      def self.owner_only_grant?(subject_type, subject_key)
        type = subject_type.to_s
        return true if OWNER_ONLY_SUBJECT_TYPES.include?(type)
        return true if type == "Route" && OwnerOnlySurfaces.controller?(subject_key)

        false
      end

      def self.remove_grant!(role, attrs)
        scope = role.role_permissions.where(
          subject_type: attrs[:subject_type] || attrs["subject_type"],
          action:       attrs[:action]       || attrs["action"]
        )
        scope = scope.where(subject_key: attrs[:subject_key] || attrs["subject_key"])
        scope = scope.where(subject_id:  attrs[:subject_id]  || attrs["subject_id"])
        scope.destroy_all
      end
    end
  end
end
