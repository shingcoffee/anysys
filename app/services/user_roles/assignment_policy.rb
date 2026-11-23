# frozen_string_literal: true

module UserRoles
  # Persisted role mutations are account-serialized, including direct model
  # writes. The replacement operation updates the reserved join in place;
  # deleting it first would temporarily leave the account without a role.
  class AssignmentPolicy
    def self.serialize(record)
      ids = [record.user_id, record.user_id_in_database].compact.uniq.sort
      Authentication::User.transaction do
        Authentication::User.where(id: ids).order(:id).lock.load
        yield
      end
    end

    def self.validate(record)
      user = Authentication::User.find_by(id: record.user_id) || record.user
      role = record.role
      return unless user && role

      if user.customer_id != role.customer_id
        record.errors.add(:role, I18n.t("admin_settings.errors.validations.role_customer_mismatch"))
      end
      if role.system? && role.key == "owner" && !user.eligible_for_owner_role?
        record.errors.add(:role, I18n.t("admin_settings.errors.validations.role_owner_reserved"))
      end

      original = record.persisted? ? UsersRole.includes(:role).find_by(id: record.id) : nil
      if original && reserved?(original.role) &&
          (original.user_id != record.user_id || !reserved?(role))
        record.errors.add(:base, I18n.t("auth.errors.reserved_role_required"))
      end
      if original&.role&.system? && original.role.key == "owner" &&
          (original.user_id != record.user_id || original.role_id != record.role_id)
        record.errors.add(:base, I18n.t("admin_settings.errors.validations.role_owner_reserved"))
      end
      if reserved?(role) && reserved_scope(record.user_id).where.not(id: record.id).exists?
        record.errors.add(:base, I18n.t("auth.errors.single_reserved_role"))
      end
    end

    def self.removable?(record)
      # Cascading deletion of the user itself does not leave an authenticated
      # roleless account. A tenant cascade removes its users as well; standalone
      # deletion of a reserved Role must still protect its assignments.
      return true if record.destroyed_by_association&.active_record == Authentication::User
      if record.destroyed_by_association&.active_record == Role &&
          record.role.destroyed_by_association&.active_record == Customer
        return true
      end

      original = UsersRole.includes(:role).find_by(id: record.id)
      return true unless original && reserved?(original.role)

      key = if original.role.key == "owner"
        "admin_settings.errors.validations.role_owner_reserved"
      elsif !reserved_scope(original.user_id).where.not(id: original.id).exists?
        "auth.errors.reserved_role_required"
      end
      return true unless key

      record.errors.add(:base, I18n.t(key))
      false
    end

    def self.reserved?(role)
      role.system? && role.reserved?
    end

    def self.reserved_scope(user_id)
      UsersRole.joins(:role).where(user_id: user_id,
        roles: { system: true, key: Authentication::User::RESERVED_ROLE_KEYS })
    end
    private_class_method :reserved_scope
  end
end
