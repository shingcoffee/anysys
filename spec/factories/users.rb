FactoryBot.define do
  factory :user, class: "Authentication::User" do
    customer
    sequence(:email) { |n| "user#{n}@example.com" }
    first_name { "Test" }
    last_name { "User" }
    password { "password123" }
    status { :active }
    confirmed_at { Time.current }

    # Support legacy `role:` keyword argument by using transient
    transient do
      role { nil }
    end

    after(:create) do |user, evaluator|
      # Map transient role parameter to RBAC assignment. The `member` role
      # is an explicit role row in `users_roles` (RouteAuthorization gates
      # /:cid/member/* on `current_user.member?`, which checks for it).
      role_key = case evaluator.role&.to_sym
      when :owner  then "owner"
      when :admin  then "admin"
      when :member then "member"
      else nil
      end

      if role_key.present?
        role_record = user.customer.roles.find_or_create_by!(key: role_key) do |r|
          r.name = role_key.capitalize
          r.system = true
          r.locked_grants = true
        end
        user.users_roles.create!(role: role_record)
      end
    end

    # Convenience trait: build a fully-pinned platform-owner user. The
    # owner role is reserved for one specific user (see AGENTS.md), so
    # specs that need a platform owner should use this trait rather than
    # ad-hoc `:owner` + custom emails.
    trait :platform_owner do
      customer do
        Customer.find_or_create_by!(id: ::Authentication::User::PLATFORM_CUSTOMER_ID) do |c|
          c.name = "Platform"
          c.industry = :technology
          c.tier = :basic
        end
      end
      email { ::Authentication::User::PLATFORM_OWNER_EMAIL }
      role { :owner }
    end

    trait :owner do
      role { :owner }
    end

    trait :admin do
      role { :admin }
    end

    trait :member do
      role { :member }
    end

    trait :inactive do
      status { :inactive }
    end

    trait :with_mfa do
      otp_secret { ROTP::Base32.random }
      otp_required_for_login { true }
    end

    trait :mfa_configured do
      otp_secret { ROTP::Base32.random }
      otp_required_for_login { false }
    end

    trait :unconfirmed do
      confirmed_at { nil }

      after(:create) do |user|
        # Clear confirmation tokens that Devise auto-generated,
        # so the user is truly unconfirmed and ready for a fresh
        # send_confirmation_instructions call
        user.update_columns(
          confirmation_token: nil,
          confirmation_sent_at: nil
        )
      end
    end
  end
end
