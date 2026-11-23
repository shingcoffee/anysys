# frozen_string_literal: true

# Authentication::User
#
# Devise-powered authentication model for multi-tenant access.
# Each user belongs to a customer (tenant) and has role-based permissions.
# Supports optional TOTP-based 2FA/MFA when enabled for the customer.
#
module Authentication
  class User < ApplicationRecord
    self.table_name = "users"

    include TenantScoped
    include User::MfaMethods
    include User::DisplayHelpers

    # The TOTP shared secret is a credential — encrypt it at rest (Rails AR
    # encryption; support_unencrypted_data is on, so existing plaintext rows read
    # transparently and re-encrypt on the next MFA change).
    encrypts :otp_secret

    # Credential and security-adjacent columns. Must not appear in email
    # template tokens, audience filters, or the Developer column picker.
    SENSITIVE_COLUMNS = %w[
      encrypted_password password otp_secret reset_password_token
      confirmation_token unlock_token sign_in_token
      otp_required_for_login failed_attempts
      current_sign_in_ip last_sign_in_ip
    ].freeze

    # Public customer sign-up creates the founder without a password. Other
    # creates still require one. See Authentication::CustomerSignup.
    attr_accessor :allow_blank_password

    # ==========================================================================
    # Devise Modules
    # ==========================================================================
    # NOTE: :validatable is intentionally absent. Presence, format, and
    # global uniqueness are declared below so they stay next to the other
    # User validations rather than split across Devise's :validatable.

    devise :database_authenticatable, :registerable, :recoverable,
           :confirmable, :rememberable, :trackable, :lockable, :timeoutable
    include User::TenantSecurityPolicy

    # ==========================================================================
    # Devise 5.0 resource-level overrides
    # ==========================================================================
    # Override .password_length at the class level to set a per-resource-class
    # password range without touching Devise's global config. The instance-level
    # delegator below lets the validation proc read it.
    #
    # Note: :registerable already installs .sign_in_after_change_password as a
    # class attribute via Devise::Models.config, so that reader is inherited.

    def self.password_length
      Devise.password_length
    end

    # ==========================================================================
    # Enums
    # ==========================================================================

    enum :status, { active: 0, inactive: 1, trashed: 2 }, default: :active

    RESERVED_ROLE_KEYS = %w[owner admin member].freeze

    # ==========================================================================
    # Role queries — backed by the RBAC `users_roles` table
    # ==========================================================================

    def owner?  = reserved_role_keys.include?("owner")
    def admin?  = reserved_role_keys.include?("admin")
    def member? = reserved_role_keys.include?("member")

    def primary_role_key
      RESERVED_ROLE_KEYS.find { |k| reserved_role_keys.include?(k) } || "member"
    end

    def role_display_name
      key = primary_role_key.to_s
      if RESERVED_ROLE_KEYS.include?(key)
        I18n.t("common.roles.#{key}")
      else
        key
      end
    end

    # ==========================================================================
    # Validations
    # ==========================================================================

    validates :email, presence: true,
                      format: { with: URI::MailTo::EMAIL_REGEXP },
                      uniqueness: { case_sensitive: false }
    validates :password,
              presence: true,
              confirmation: true,
              length: {
                minimum: proc { password_length.min },
                maximum: proc { password_length.max }
              },
              if: :password_required?
    validates :first_name, presence: true, length: { maximum: 50 }
    validates :last_name, presence: true, length: { maximum: 50 }
    validates :customer_id, presence: true
    # Optional UI language preference. Blank = follow the request fallback chain.
    validates :locale, inclusion: { in: ->(_) { I18n.available_locales.map(&:to_s) } },
                       allow_blank: true
    validate :validate_owner_identity

    # ==========================================================================
    # Scopes
    # ==========================================================================

    scope :active,               -> { where(status: :active) }
    scope :by_role,              ->(role_key) do
      joins(:roles).where(roles: { key: role_key.to_s, system: true }).distinct
    end
    scope :by_name,              -> { order(:last_name, :first_name) }

    # ==========================================================================
    # RBAC associations (Phase 1)
    # ==========================================================================

    has_many :users_roles, foreign_key: :user_id, dependent: :destroy
    has_many :roles, through: :users_roles

    has_many :trusted_devices,
             class_name: "Authentication::TrustedDevice",
             foreign_key: :user_id,
             dependent: :delete_all

    has_many :person_entries,
             class_name: "EntityEntry",
             foreign_key: :user_id,
             inverse_of: :user
    before_destroy { person_entries.each { |entry| People::Link.detach!(entry, self) } }

    # A credential change must not leave anything minted under the old
    # credential alive. Devise's cookie sessions and remember-me cookies are
    # keyed off `authenticatable_salt` (the leading bytes of
    # encrypted_password), so a password change invalidates those for free.
    # The lifecycle service revokes trusted devices, OAuth codes/tokens and
    # sign-in links in the same transaction, under the account lock. Email and
    # customer changes are authentication-identity changes too.
    around_update :apply_credential_lifecycle

    # @param key [Symbol, String] one of :owner, :admin, :member
    def has_reserved_role?(key)
      reserved_role_keys.include?(key.to_s)
    end

    def reserved_role_keys
      roles.select { |r| r.system? }.map(&:key)
    end

    # ==========================================================================
    # Devise Overrides (Multi-Tenant)
    # ==========================================================================

    # The single case-insensitive email lookup for the whole authentication
    # surface (Warden, password reset, unlock, confirmation resend, sign-in
    # link). Email is globally unique and backed by a unique index on
    # LOWER(email), so no tenant scope is needed — and every caller sharing
    # one implementation is what keeps a missing address on exactly the same
    # code path as a present one. Chain off a scope to narrow, e.g.
    # `active.find_by_normalized_email(email)`.
    def self.find_by_normalized_email(email)
      normalized = email.to_s.downcase.strip
      return nil if normalized.blank?

      find_by("LOWER(email) = ?", normalized)
    end

    # Email is globally unique, so lookup is by email alone. customer_id in
    # warden conditions (if a caller still passes it) is ignored.
    def self.find_for_database_authentication(warden_conditions)
      conditions = warden_conditions.dup
      conditions.delete(:customer_id)

      active.find_by_normalized_email(conditions.delete(:email))
    end

    # ==========================================================================
    # Devise recovery overrides
    # ==========================================================================
    # Email is globally unique, so stock Devise email-only lookup is safe.
    # These overrides still exist so a missing user always returns a stub
    # (identical timing) and so password-reset / confirmation resend no-op
    # when that user's tenant has the matching feature disabled.

    def self.send_reset_password_instructions(attributes = {})
      recover_by_email(:send_reset_password_instructions, attributes) do |user|
        user.password_reset_available?
      end
    end

    # Whether this user's tenant currently permits password reset. Consulted
    # by BOTH sides of the flow — issuing the email here, and consuming the
    # token in PasswordsController — so a token issued while the toggle was on
    # cannot still be redeemed after an admin turns it off. Keeping it in one
    # place is the point: the consume side had no check at all, which made
    # disabling password reset useless as an incident-response control.
    def password_reset_available?
      self.class.authentication_enabled?(self) &&
        Authentication::Settings.for(customer_id).password_reset_enabled?
    end

    def self.send_unlock_instructions(attributes = {})
      recover_by_email(:send_unlock_instructions, attributes) do |user|
        authentication_enabled?(user)
      end
    end

    def self.send_confirmation_instructions(attributes = {})
      recover_by_email(:send_confirmation_instructions, attributes) do |user|
        authentication_enabled?(user) && confirmation_resend_allowed?(user)
      end
    end

    # Look the user up by email, yield to decide whether to dispatch, and
    # always return a resource (a stub with an :email error when no match)
    # so timing/response is identical for missing users.
    def self.recover_by_email(devise_instance_method, attributes)
      attrs = normalize_recovery_attributes(attributes)
      user = find_by_normalized_email(attrs[:email])
      return new.tap { |u| u.errors.add(:email, :not_found) } unless user
      return user unless yield(user)

      user.public_send(devise_instance_method)
      user
    end
    private_class_method :recover_by_email

    def self.authentication_enabled?(user)
      FeatureModules::Module.enabled?(key: "authentication", customer_id: user.customer_id)
    end

    # Member confirmation resend stays gated by the tenant sign-up toggle.
    # A self-serve customer admin can resend while the tenant is still inactive.
    def self.confirmation_resend_allowed?(user)
      return true if user.admin? && !user.confirmed?

      Authentication::Settings.for(user.customer_id).signup_enabled?
    end
    private_class_method :confirmation_resend_allowed?

    # Devise hands us the form params either as a Hash or as
    # ActionController::Parameters. Normalize to a HashWithIndifferentAccess
    # so symbol/string keys both work.
    def self.normalize_recovery_attributes(attributes)
      hash =
        if attributes.respond_to?(:to_unsafe_h)
          attributes.to_unsafe_h
        else
          attributes.to_h
        end
      hash.with_indifferent_access
    end
    private_class_method :normalize_recovery_attributes

    # ==========================================================================
    # Role / Platform-Owner Predicates
    # ==========================================================================

    def admin_or_owner?
      admin? || owner?
    end

    # ==========================================================================
    # Per-request activation gate
    # ==========================================================================
    # The custom `status` enum was previously enforced only at login
    # (`find_for_database_authentication` filters `status: :active`), so a
    # session established while active survived deactivation — an admin could
    # not actually revoke a live user. Overriding Devise's per-request
    # `active_for_authentication?` routes the status enum through Warden's
    # `activatable` hook, which logs out an inactive user on their next request.
    def active_for_authentication?
      super && active?
    end

    # Keeps the account, its sign-in, and its profile links, and hides it from
    # the directory. Restore puts it back as an active account.
    def move_to_trash
      update(status: :trashed)
    end

    def restore_from_trash
      update(status: :active)
    end

    def inactive_message
      active? ? super : :deactivated
    end

    PLATFORM_CUSTOMER_ID = 81_721_200
    PLATFORM_OWNER_EMAIL = "lingercoffee@gmail.com"

    # Check if user belongs to platform owner customer (81721200) with owner role.
    # These users can access platform-wide management features.
    def platform_owner?
      owner? && eligible_for_owner_role?
    end

    # The owner role is reserved for a single, specific user. See AGENTS.md
    # "Reserved Roles & Access Rules". Used by UsersRole to gate assignment.
    def eligible_for_owner_role?
      customer_id == PLATFORM_CUSTOMER_ID &&
        email.to_s.downcase.strip == PLATFORM_OWNER_EMAIL
    end

    def password_set?
      encrypted_password.present?
    end

    private

    def validate_owner_identity
      OwnerIdentity.validate(self)
    end

    def apply_credential_lifecycle(&block)
      CredentialLifecycle.around_update(self, &block)
    end

    # Devise: determine if password validation is required
    def password_required?
      if ActiveModel::Type::Boolean.new.cast(allow_blank_password) &&
          password.blank? && password_confirmation.blank?
        return false
      end

      !persisted? || password.present? || password_confirmation.present?
    end

    # Instance-level delegator so the validation proc can reach the class-level
    # .password_length override.
    def password_length
      self.class.password_length
    end

    # Devise mail is enqueued, never sent on the request thread: SMTP latency
    # would time which addresses have accounts.
    def send_devise_notification(notification, *args)
      devise_mailer.send(notification, self, *args).deliver_later
    end
  end
end
