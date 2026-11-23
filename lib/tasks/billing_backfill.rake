# frozen_string_literal: true

namespace :billing do
  desc "Explicitly enroll customers using the permanent free-onboarding request identity"
  task backfill_subscriptions: :environment do
    outcomes = Hash.new(0)
    Customer.find_each { |customer| outcomes[Billing::Onboarding.call(customer).status] += 1 }
    puts outcomes.inspect
  end
end
