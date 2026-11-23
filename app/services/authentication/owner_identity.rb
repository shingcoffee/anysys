# frozen_string_literal: true

module Authentication
  # The pin belongs to the persisted account, not to a cached role predicate.
  # Keep it intact even during provisioning before its owner join is inserted.
  class OwnerIdentity
    def self.validate(user)
      return unless user.persisted?
      return unless user.will_save_change_to_email? || user.will_save_change_to_customer_id?

      email, customer_id = User.where(id: user.id).pick(:email, :customer_id)
      pinned = customer_id == User::PLATFORM_CUSTOMER_ID &&
        email.to_s.downcase.strip == User::PLATFORM_OWNER_EMAIL
      owner = user.users_roles.joins(:role).where(roles: { system: true, key: "owner" }).exists?
      return unless pinned || owner

      message = I18n.t("admin_settings.errors.validations.role_owner_reserved")
      user.errors.add(:email, message) unless user.email.to_s.downcase.strip == User::PLATFORM_OWNER_EMAIL
      user.errors.add(:customer_id, message) unless user.customer_id == User::PLATFORM_CUSTOMER_ID
    end
  end
end
