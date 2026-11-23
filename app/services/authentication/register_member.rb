# frozen_string_literal: true

module Authentication
  # Shared member sign-up used by the public registration form and the
  # flowchart `register_member` step. The customer lock, member quota,
  # persist, and reserved member role share one transaction. Devise
  # confirmable already sends instructions after that transaction commits.
  class RegisterMember
    Result = Struct.new(:status, :user, :errors, keyword_init: true)

    ATTRIBUTE_KEYS = %i[first_name last_name email password password_confirmation].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(customer:, attributes:, request: nil, passwordless: false)
      @customer = customer
      @attributes = attributes
      @request = request
      @passwordless = passwordless
    end

    def call
      user = build_user
      guard = nil
      saved = false

      begin
        @customer.with_lock(requires_new: true) do
          guard = Billing::Quota::Guard.check(customer: @customer, item_key: "member")
          saved = user.save && assign_member_role!(user) if guard.allowed?
        end
      rescue ActiveRecord::RecordInvalid
        user.errors.add(:base, I18n.t("auth.errors.reserved_role_required"))
      rescue ActiveRecord::RecordNotUnique
        user.errors.add(:email, :taken)
      end

      unless guard&.allowed?
        user.errors.add(:base, guard.message) if guard
        return Result.new(status: :quota_exceeded, user: user, errors: user.errors)
      end

      status = saved ? :created : :invalid
      Result.new(status: status, user: user, errors: user.errors)
    end

    private

    def build_user
      user = User.new(normalized_attributes)
      user.customer_id = @customer.id
      user.allow_blank_password = true if @passwordless
      user
    end

    def normalized_attributes
      hash =
        if @attributes.respond_to?(:to_unsafe_h)
          @attributes.to_unsafe_h
        else
          @attributes.to_h
        end
      hash.with_indifferent_access.slice(*ATTRIBUTE_KEYS)
    end

    def assign_member_role!(user)
      role = user.customer.roles.find_or_create_by!(key: "member") do |r|
        r.name = I18n.t("common.roles.member")
        r.system = true
        r.locked_grants = true
      end
      before_role_ids = user.users_roles.pluck(:role_id)
      user.users_roles.find_or_create_by!(role: role)
      MutationAudit.roles(user: user, before_role_ids: before_role_ids, request: @request)
      true
    end
  end
end
