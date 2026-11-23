FactoryBot.define do
  factory :page do
    sequence(:name) { |n| "Page #{n}" }
    description { "A sample page for testing purposes" }
    customer
    transient do
      entity { nil }
    end

    after(:build) do |page, evaluator|
      bound_entity = evaluator.entity || (
        page.shared? ? create(:entity, :shared) : create(:entity, customer: page.customer)
      )
      config = JSON.parse(page.configuration || "{}")
      config["metadata"] ||= {}
      config["metadata"]["entity_id"] = bound_entity.id
      config["metadata"]["entity_name"] = bound_entity.name
      config["metadata"]["created_at"] ||= Time.current.iso8601
      config["pages"] ||= [{ "id" => "page_1", "name" => "Page 1", "order" => 1, "fields" => [] }]
      page.configuration = config.to_json
    end

    content { nil }

    trait :shared do
      customer { nil }
      after(:build) { |record| record.skip_tenant_customer_assignment! }
    end

    trait :for_member do
      audience_member { true }
    end

    trait :for_public do
      audience_public { true }
    end

    trait :member_only do
      audience_admin { false }
      audience_member { true }
      audience_public { false }
    end

    trait :public_only do
      audience_admin { false }
      audience_member { false }
      audience_public { true }
    end

    trait :launched do
      launched { true }
    end
  end
end
