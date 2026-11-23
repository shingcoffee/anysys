FactoryBot.define do
  factory :feature_module, class: "FeatureModules::Module" do
    sequence(:key) { |n| "module_#{n}" }
    sequence(:name) { |n| "Module #{n}" }
    description { "A test feature module" }
    configuration_schema { {}.to_json }
    status { :active }

    trait :inactive do
      status { :inactive }
    end

    trait :handoffable do
      handoff_enabled { true }
    end
  end

  factory :customer_feature_module, class: "FeatureModules::CustomerAssignment" do
    customer
    feature_module
    configuration { {}.to_json }
    status { :active }
    enabled_at { Time.current }

    trait :suspended do
      status { :suspended }
    end
  end

  factory :feature_module_log, class: "FeatureModules::Log" do
    customer
    feature_module
    action { "test_action" }
    request_data { {}.to_json }
    response_data { {}.to_json }
    status { :success }

    trait :failure do
      status { :failure }
      error_message { "Something went wrong" }
    end
  end
end
