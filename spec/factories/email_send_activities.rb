FactoryBot.define do
  factory :email_send_activity, class: "Emails::SendActivities::SendActivity" do
    customer
    email_template { customer ? create(:email_template, customer: customer) : nil }
    sequence(:name) { |n| "Send Activity #{n}" }
    status { "pending" }
    scheduled_at { 1.hour.from_now }
    timezone { "UTC" }
    stats { {} }

    transient do
      email_lists { nil }
    end

    after(:build) do |activity, evaluator|
      lists = evaluator.email_lists
      lists = [create(:email_list, customer: activity.customer)] if lists.nil? && activity.customer
      activity.email_lists = Array(lists) if lists
    end

    trait :pending do
      status { "pending" }
      scheduled_at { 1.hour.from_now }
    end

    trait :processing do
      status { "processing" }
      started_at { Time.current }
      scheduled_at { Time.current }
    end

    trait :succeed do
      status { "succeed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      scheduled_at { 1.hour.ago }
    end

    trait :recurring do
      recurrence_rule { "FREQ=DAILY;INTERVAL=1" }
    end
  end
end
