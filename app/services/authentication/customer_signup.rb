# frozen_string_literal: true

module Authentication
  # Public tenant creation. Builds a Customer and a confirmed admin User
  # (inbox already proven by CustomerSignupToken) with no password. The
  # Authentication provisioner is skipped so no dummy admin is created.
  class CustomerSignup
    Result = Struct.new(:success?, :user, :customer, :errors, keyword_init: true)

    DEFAULT_INDUSTRY = "technology"

    def self.call(...)
      new(...).call
    end

    def initialize(email:)
      @email = email.to_s.strip.downcase
    end

    def call
      return disabled_failure unless PlatformSettings.customer_signup_enabled?

      customer = nil
      user = nil

      Customer.transaction(requires_new: true) do
        customer = build_customer
        customer.skip_authentication_provisioner = true
        customer.save!

        if customer.id == User::PLATFORM_CUSTOMER_ID
          customer.errors.add(:base, I18n.t("auth.customer_registrations.errors.retry"))
          raise ActiveRecord::Rollback
        end

        user = build_user(customer)
        unless user.save
          raise ActiveRecord::Rollback
        end

        assign_admin!(user, customer)
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, user: user, customer: customer, errors: [ e.record.errors.full_messages.presence || e.message ].flatten)
    rescue ActiveRecord::RecordNotUnique
      # Two concurrent confirms of the same link — a double-clicked email
      # button, or a mail client prefetching while the human clicks. Neither
      # request sees the other's uncommitted row, so both pass the uniqueness
      # *validation* and the loser hits the unique index on LOWER(email)
      # instead. Uncaught, that surfaced as a 500 on a flow the user had in
      # fact completed. The transaction has rolled the loser's Customer back,
      # so there is no orphan tenant; report it as a plain failure and let the
      # caller re-resolve the now-committed account.
      Result.new(success?: false, user: nil, customer: nil,
                 errors: [ I18n.t("auth.customer_registrations.errors.retry") ])
    else
      if user&.persisted?
        Result.new(success?: true, user: user, customer: customer, errors: [])
      else
        Result.new(success?: false, user: user, customer: customer, errors: collect_errors(user, customer))
      end
    end

    private

    def disabled_failure
      Result.new(success?: false, user: nil, customer: nil,
                 errors: [ I18n.t("auth.customer_registrations.disabled.body") ])
    end

    def build_customer
      Customer.new(
        name: default_name,
        industry: DEFAULT_INDUSTRY,
        status: :active,
        role: :admin,
        tier: :basic
      )
    end

    def build_user(customer)
      local = @email.split("@", 2).first.to_s
      parts = local.split(/[._-]+/).reject(&:blank?)
      first = (parts[0] || local).presence || "Admin"
      last  = (parts[1] || "Admin")

      user = User.new(
        customer: customer,
        email: @email,
        first_name: first.to_s.truncate(50),
        last_name: last.to_s.truncate(50),
        status: :active,
        allow_blank_password: true
      )
      user.skip_confirmation!
      user
    end

    def assign_admin!(user, customer)
      role = customer.roles.system.find_by!(key: "admin")
      user.users_roles.create!(role: role)
    end

    def default_name
      local = @email.split("@", 2).first.to_s
      name = local.tr("._-", " ").squeeze(" ").strip.titleize
      name = "Organization" if name.blank?
      name.truncate(100)
    end

    def collect_errors(user, customer)
      errs = []
      errs.concat(user.errors.full_messages) if user
      errs.concat(customer.errors.full_messages) if customer&.errors&.any?
      errs.presence || [ I18n.t("auth.customer_registrations.errors.failed") ]
    end
  end
end
