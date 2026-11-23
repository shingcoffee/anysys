# frozen_string_literal: true

FactoryBot.define do
  factory :role_permission do
    role
    subject_type { "Route" }
    subject_key  { "admin/maintenance/flowcharts" }
    subject_id   { nil }
    action       { "read" }

    trait :entity_class do
      subject_type { "EntityClass" }
      subject_key  { "Entity" }
      subject_id   { nil }
      action       { "manage" }
    end

    trait :entity_instance do
      subject_type { "Entity" }
      subject_key  { nil }
      subject_id   { 42 }
      action       { "update" }
    end
  end
end
