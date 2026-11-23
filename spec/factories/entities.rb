FactoryBot.define do
  factory :entity do
    sequence(:name) { |n| "Entity #{n}" }
    display_label { name }
    description { "A sample entity for testing purposes" }
    icon { "custom" }
    color { "#6366f1" }
    property_schema { [].to_json }
    default_properties { {}.to_json }
    customer

    trait :shared do
      customer { nil }
      after(:build) { |record| record.skip_tenant_customer_assignment! }
    end

    trait :with_name_status_schema do
      property_schema do
        [
          { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" },
          { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text" }
        ].to_json
      end
    end

    trait :with_amount_schema do
      property_schema do
        [
          { "name" => "Amount", "name_slug" => "amount", "type" => "Float", "html_type" => "number" }
        ].to_json
      end
    end
  end
end
