# frozen_string_literal: true

FactoryBot.define do
  factory :page_shortcut do
    customer { target.customer }
    sequence(:path) { |n| "/shortcut-#{n}" }
    association :target, factory: :page
  end
end
