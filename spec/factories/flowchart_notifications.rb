# frozen_string_literal: true

FactoryBot.define do
  factory :flowchart_notification do
    customer
    user { association :user, :member, customer: customer }
    title { { "en" => "Notice" } }
    body { { "en" => "Your request was received." } }
  end
end
