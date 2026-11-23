# frozen_string_literal: true

namespace :payments do
  namespace :historical_bindings do
    desc "Report deterministic old payment/event merchant bindings without changing data"
    task preflight: :environment do
      require Rails.root.join("db/data_migrations/payment_historical_bindings_v1")
      report = PaymentHistoricalBindingsV1.new.call
      puts JSON.pretty_generate(report)
      abort "Historical merchant evidence is unresolved; no data was changed." if report.fetch("unresolved").any?
    end

    desc "Apply deterministic historical identities only if the entire preflight resolves"
    task apply: :environment do
      require Rails.root.join("db/data_migrations/payment_historical_bindings_v1")
      report = PaymentHistoricalBindingsV1.new.call(apply: true)
      puts JSON.pretty_generate(report)
    rescue PaymentHistoricalBindingsV1::UnresolvedBindings => error
      puts JSON.pretty_generate(error.report)
      abort error.message
    end
  end
end
