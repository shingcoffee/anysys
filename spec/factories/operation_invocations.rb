# frozen_string_literal: true

FactoryBot.define do
  factory :operation_invocation do
    customer
    user { association :user, :admin, customer: customer }
    operation { "fake_echo" }
    operation_version { 1 }
    channel { "assistant" }
    status { "succeeded" }
    input { { "name" => "Alpha" } }
    plan { [] }
    snapshot { {} }
    result { { "status" => "succeeded", "operation" => "fake_echo" } }
    violations { [] }

    trait :awaiting_confirmation do
      operation { "fake_update" }
      status { "awaiting_confirmation" }
      plan { [{ "kind" => "echo", "name" => "Alpha" }] }
      snapshot { { "name" => "Alpha" } }
    end
  end
end
