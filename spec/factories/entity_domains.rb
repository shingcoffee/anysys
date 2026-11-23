# frozen_string_literal: true

FactoryBot.define do
  factory :entity_domain do
    sequence(:name) { |n| "Domain #{n}" }
    color { "blue" }
    customer
  end
end
