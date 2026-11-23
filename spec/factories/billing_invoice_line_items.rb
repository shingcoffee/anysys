# frozen_string_literal: true

FactoryBot.define do
  factory :billing_invoice_line_item, class: "Billing::InvoiceLineItem" do
    customer
    association :invoice, factory: :billing_invoice
    description      { "Subscription charge" }
    quantity         { 1 }
    unit_amount_cents { 9900 }
    amount_cents     { 9900 }
    kind             { "subscription" }

    trait :proration do
      kind { "proration" }
    end

    trait :discount do
      kind             { "discount" }
      unit_amount_cents { -2000 }
      amount_cents     { -2000 }
    end

    trait :tax do
      kind { "tax" }
    end
  end
end
