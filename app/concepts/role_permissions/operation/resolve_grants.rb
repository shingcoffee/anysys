# frozen_string_literal: true

module RolePermissions
  module Operation
    class ResolveGrants
      # @param role_ids [Array<Integer>]
      # @return [Array<RolePermission>]
      def self.call(role_ids:)
        return [] if Array(role_ids).empty?

        RolePermission.where(role_id: role_ids).to_a
      end
    end
  end
end
