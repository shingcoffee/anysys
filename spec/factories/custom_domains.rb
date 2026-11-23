# frozen_string_literal: true

FactoryBot.define do
  factory :custom_domain, class: "CustomDomainRecord::Row" do
    customer
    sequence(:domain) { |n| "customer-#{n}.example.test" }

    initialize_with { CustomDomainRecord::Row.new(domain: domain, customer_id: customer.id) }

    to_create do |row|
      customer = Customer.unscoped.find(row.customer_id)
      customer.update_columns(domain: row.domain)
    end
  end
end
