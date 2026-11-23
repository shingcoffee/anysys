# frozen_string_literal: true

FactoryBot.define do
  factory :flowchart_sequence do
    customer
    sequence(:name) { |n| "seq_#{n}" }
    period { "never" }
    last_value { 0 }
  end
end
