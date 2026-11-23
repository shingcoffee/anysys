# frozen_string_literal: true

FactoryBot.define do
  factory :billing_payment_method, class: "Billing::PaymentMethod" do
    customer
    provider      { "alipay" }
    status        { "pending" }
    is_default    { false }
    display_label { nil }
    authorized_at { nil }
    sequence(:request_key) { |n| "test-method:#{n}" }
    revocation_state { "none" }
    merchant_account do
      platform = Customer.find_or_create_by!(id: 81_721_200) { |row| row.name = "Platform"; row.industry = :technology }
      Payments::MerchantAccount.unscoped_by_tenant.find_by(customer_id: platform.id, provider: provider, mode: "sandbox") ||
        association(:payment_merchant_account, provider.to_sym, customer: platform)
    end

    trait :active do
      status        { "active" }
      display_label { "Alipay (authorized)" }
      authorized_at { Time.zone.now }
      is_default    { true }
    end

    trait :failed do
      status { "failed" }
    end

    trait :removed do
      status     { "removed" }
      is_default { false }
    end

    trait :wechat_pay do
      provider      { "wechat_pay" }
      display_label { "WeChat Pay (authorized)" }
    end
  end
end
