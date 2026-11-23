# frozen_string_literal: true

module Roles
  module Operation
    class SeedReserved
      RESERVED = [
        { key: "owner",  name: "Owner",
          description: "Full access. Reserved system role." },
        { key: "admin",  name: "Admin",
          description: "Admin-area access except platform tools. Reserved system role." },
        { key: "member", name: "Member",
          description: "Member without admin access. Reserved system role." }
      ].freeze

      # @param customer [Customer]
      # @return [Array<Role>]
      def self.call(customer:)
        roles = RESERVED.map do |attrs|
          Role.find_or_create_by!(customer: customer, key: attrs[:key]) do |r|
            r.name          = attrs[:name]
            r.description   = attrs[:description]
            r.system        = true
            r.locked_grants = true
          end
        end

        admin_role = roles.find { |r| r.key == "admin" }
        seed_admin_grants(customer, admin_role) if admin_role

        roles
      end

      # Seed grants for admin role from the access-points catalog.
      # Idempotent — skips if grants already exist.
      #
      # Grants are bulk-inserted in a single statement: the catalog is the
      # trusted source the RolePermission validations mirror, and the model
      # has no callbacks, so bypassing per-row AR instantiation is safe and
      # ~6x faster (the dominant cost of provisioning a customer).
      #
      # @param customer [Customer]
      # @param admin_role [Role]
      def self.seed_admin_grants(customer, admin_role)
        return if admin_role.role_permissions.exists? # idempotent

        Current.access_points_catalog = nil
        catalog = AccessPoints::Catalog.for(customer_id: customer.id)
        now = Time.current
        rows = catalog.groups.flat_map do |group|
          next [] if group[:key] == "platform" || group[:key].start_with?("admin.maintenance.platform") # skip platform-only routes

          group[:descriptors].flat_map do |d|
            assert_grant_shape!(d)

            d.actions.map do |action|
              {
                role_id:      admin_role.id,
                subject_type: d.subject_type,
                subject_key:  d.subject_key,
                subject_id:   d.subject_id,
                action:       action.to_s,
                created_at:   now,
                updated_at:   now
              }
            end
          end
        end
        RolePermission.insert_all!(rows) if rows.any?
      ensure
        Current.access_points_catalog = nil
      end

      # insert_all! bypasses RolePermission's AR validations, so this mirrors
      # RolePermission#subject_shape_valid in plain Ruby to keep a malformed
      # catalog descriptor a loud programming error instead of a silent bad insert.
      #
      # @param descriptor [AccessPoints::Descriptor]
      def self.assert_grant_shape!(descriptor)
        type, key, id = descriptor.subject_type, descriptor.subject_key, descriptor.subject_id

        if RolePermission::KEY_BASED_TYPES.include?(type)
          raise ArgumentError, "descriptor #{descriptor.inspect} requires subject_key and forbids subject_id for type #{type}" if key.blank? || id.present?
        elsif RolePermission::INSTANCE_BASED_TYPES.include?(type)
          raise ArgumentError, "descriptor #{descriptor.inspect} requires subject_id and forbids subject_key for type #{type}" if id.blank? || key.present?
        else
          raise ArgumentError, "descriptor #{descriptor.inspect} has unrecognized subject_type #{type.inspect}"
        end
      end
    end
  end
end
