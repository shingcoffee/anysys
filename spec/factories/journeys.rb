# frozen_string_literal: true

FactoryBot.define do
  factory :journey do
    customer
    entity_domain { association :entity_domain, customer: customer }
    sequence(:key) { |n| "journey_#{n}" }
    sequence(:name) { |n| "Journey #{n}" }
    definition do
      {
        "steps" => [
          { "key" => "start", "kind" => "create", "action_key" => "student_new" },
          { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course",
            "inputs" => { "student" => "start" }, "repeat" => true },
          { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
        ]
      }.to_json
    end

    trait :launched do
      status { :launched }
    end
  end
end
