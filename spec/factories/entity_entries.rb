FactoryBot.define do
  factory :entity_entry do
    customer
    entity { association :entity, customer: customer }
    data { {}.to_json }

    trait :with_data do
      transient do
        entry_data { {} }
      end
      data { entry_data.to_json }
    end
  end
end
