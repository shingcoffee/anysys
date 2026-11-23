# frozen_string_literal: true

namespace :billing do
  desc "Report billing integrity conflicts without writes, enrollment, or provider calls"
  task repair_report: :environment do
    require Rails.root.join("db/migrate/20261011000100_add_billing_subscription_lifecycle")
    report = AddBillingSubscriptionLifecycle.report(ActiveRecord::Base.connection)
    puts JSON.pretty_generate(report)
    abort "Billing preflight requires explicit owner reconciliation" if report.any?
  end
end
