# frozen_string_literal: true

FactoryBot.define do
  factory :email_list, class: "Emails::Audience::List" do
    customer
    sequence(:name) { |n| "List #{n}" }
    description { "Test list" }
    list_type { "static" }
    segment_rules { {} }

    trait :dynamic do
      list_type { "dynamic" }
      segment_rules do
        {
          "match" => "all",
          "conditions" => [
            { "field" => "first_name", "operator" => "equals", "value" => "Ada" }
          ]
        }
      end
    end

    trait :static do
      list_type { "static" }
    end
  end
end
