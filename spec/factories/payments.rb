# frozen_string_literal: true

FactoryBot.define do
  factory :payment_merchant_account, class: "Payments::MerchantAccount" do
    customer { Current.customer || association(:customer) }
    provider { "stripe" }
    mode { "sandbox" }
    status { "active" }
    sequence(:merchant_id) { |n| "acct_#{n}" }

    transient do
      default_credentials { {} }
      credentials { {} }
    end

    after(:build) do |account, evaluator|
      merged = evaluator.default_credentials.merge(evaluator.credentials || {})
      account.write_credentials(merged) if merged.present?
    end

    trait :disabled do
      status { "disabled" }
    end

    trait :production do
      mode { "production" }
    end

    trait :stripe do
      provider { "stripe" }
      sequence(:merchant_id) { |n| "acct_#{n}" }
      default_credentials do
        {
          secret_key: "sk_test_x",
          publishable_key: "pk_test_x",
          webhook_signing_secret: "whsec_test"
        }
      end
    end

    trait :alipay do
      provider { "alipay" }
      sequence(:merchant_id) { |n| "2088#{n}" }
      default_credentials do
        {
          private_key_pem: File.read(Rails.root.join("spec/fixtures/payments/keys/test_rsa_private.pem")),
          platform_public_key_pem: File.read(Rails.root.join("spec/fixtures/payments/keys/test_rsa_public.pem"))
        }
      end
    end

    trait :wechat_pay do
      provider { "wechat_pay" }
      sequence(:merchant_id) { |n| "wx_#{n}" }
      default_credentials do
        {
          appid: "wxappid",
          api_key_v3: "k",
          private_key_pem: File.read(Rails.root.join("spec/fixtures/payments/keys/test_rsa_private.pem")),
          platform_public_key_pem: File.read(Rails.root.join("spec/fixtures/payments/keys/test_rsa_public.pem")),
          wechat_cert_serial: "S1"
        }
      end
    end

    trait :paypal do
      provider { "paypal" }
      sequence(:merchant_id) { |n| "PP-MID-#{n}" }
      default_credentials do
        {
          client_id: "client",
          client_secret: "secret",
          webhook_id: "wh_id"
        }
      end
    end
  end

  factory :payment_order, class: "Payments::Order" do
    customer { Current.customer || association(:customer) }
    sequence(:external_ref) { |n| "ord_#{n}" }
    amount { 1.00 }
    currency { "CNY" }
    subject { "s" }
    status { "pending" }
  end

  factory :payment, class: "Payments::Payment" do
    customer { Current.customer || association(:customer) }
    payment_order { association :payment_order, customer: customer }
    provider { "stripe" }
    flow { "qr" }
    sequence(:out_trade_no) { |n| "otn_#{n}" }
    amount { 1.00 }
    status { "created" }
  end

  factory :payment_method, class: "Payments::PaymentMethod" do
    customer { Current.customer || association(:customer) }
    provider { "stripe" }
    sequence(:psp_customer_id) { |n| "cus_#{n}" }
    sequence(:psp_payment_method_id) { |n| "pm_#{n}" }
    brand { "visa" }
    last4 { "4242" }
    exp_month { 12 }
    exp_year { 2099 }
    status { "active" }

    transient do
      user { nil }
    end

    user_id do
      (user || association(:user, :member, customer: customer)).id
    end

    trait :pending_token do
      sequence(:psp_payment_method_id) { |n| "pending:setup_#{n}" }
    end

    trait :removed do
      status { "removed" }
      is_default { false }
    end
  end

  factory :payment_subscription, class: "Payments::Subscription" do
    customer { Current.customer || association(:customer) }
    provider { "stripe" }
    sequence(:external_ref) { |n| "sub_#{n}" }
    plan_name { "Gold" }
    amount { 20.00 }
    currency { "usd" }
    cycle { "monthly" }
    status { "active" }
  end

  factory :payment_refund, class: "Payments::Refund" do
    customer { Current.customer || association(:customer) }
    payment { association :payment, customer: customer }
    sequence(:out_refund_no) { |n| "re_#{n}" }
    amount { 1.00 }
    status { "requested" }
  end

  factory :payment_dispute, class: "Payments::Dispute" do
    customer { Current.customer || association(:customer) }
    payment { association :payment, customer: customer }
    provider { "stripe" }
    sequence(:psp_dispute_id) { |n| "dp_#{n}" }
    amount { 1.00 }
    status { "open" }
  end

  factory :payment_webhook_event, class: "Payments::WebhookEvent" do
    provider { "stripe" }
    sequence(:psp_event_id) { |n| "evt_#{n}" }
    event_type { "charge.succeeded" }
    status { "received" }
    payload { {} }
  end
end
