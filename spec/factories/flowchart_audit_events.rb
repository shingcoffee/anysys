# frozen_string_literal: true

FactoryBot.define do
  factory :flowchart_audit_event do
    customer
    event_type { "record_updated" }
    severity { "info" }
    metadata { {} }
    created_at { Time.current }
  end
end
