# frozen_string_literal: true

module UserRoles
  module Operation
    class Assign
      Result = Roles::Operation::Create::Result

      def self.call(user:, role_ids:, actor: nil, request: nil)
        ids = Array(role_ids).map(&:to_i).uniq

        user.with_lock(requires_new: true) do
          roles_by_id = user.customer.roles.where(id: ids).index_by(&:id)
          assigned = ids.map { |id| roles_by_id[id] }
          existing = user.users_roles.includes(:role).to_a
          before_role_ids = existing.map(&:role_id)
          owner = existing.find { |join| join.role.system? && join.role.key == "owner" }

          if owner
            next failure(user, "auth.errors.owner_role_protected") unless actor&.owner?
            unless ids.include?(owner.role_id)
              next failure(user, "admin_settings.errors.validations.role_owner_reserved")
            end
          end
          next failure(user, "admin_modules.flash.users.invalid_role") if assigned.any?(&:nil?)

          reserved = assigned.select { |role| AssignmentPolicy.reserved?(role) }
          next failure(user, "auth.errors.single_reserved_role") if reserved.size > 1
          next failure(user, "auth.errors.reserved_role_required") if reserved.empty?
          # Interactive replacement cannot mint an owner assignment. Initial
          # provisioning uses the pinned UsersRole model write instead.
          if reserved.first.key == "owner" && owner.nil?
            next failure(user, "auth.errors.owner_role_protected")
          end

          current_reserved = existing.select { |join| AssignmentPolicy.reserved?(join.role) }
          next failure(user, "auth.errors.single_reserved_role") if current_reserved.size > 1

          if (join = current_reserved.first)
            join.update!(role: reserved.first) unless join.role_id == reserved.first.id
          else
            user.users_roles.create!(role: reserved.first)
          end

          existing.reject { |item| AssignmentPolicy.reserved?(item.role) }.each do |item|
            item.destroy! unless ids.include?(item.role_id)
          end
          assigned.reject { |role| AssignmentPolicy.reserved?(role) }.each do |role|
            user.users_roles.find_or_create_by!(role: role)
          end
          user.association(:roles).reset
          user.association(:users_roles).reset
          Authentication::MutationAudit.roles(user: user, before_role_ids: before_role_ids,
                                                request: request, actor: actor)
          Result.new(success?: true, model: user, errors: nil)
        end
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
        messages = e.record.errors.full_messages
        messages = [I18n.t("admin_modules.flash.users.invalid_role")] if messages.blank?
        Result.new(success?: false, model: user, errors: { base: messages })
      end

      def self.failure(user, key)
        Result.new(success?: false, model: user, errors: { base: [I18n.t(key)] })
      end
      private_class_method :failure
    end
  end
end
