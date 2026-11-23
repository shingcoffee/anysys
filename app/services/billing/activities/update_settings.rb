# frozen_string_literal: true

module Billing
  module Activities
    class UpdateSettings
      def self.call(settings:, params:)
        form = Contracts::Settings.new(settings)
        unless form.validate(params)
          return Billing::Result.new(status: :invalid, record: settings, form: form, errors: form.errors.messages)
        end
        settings.with_lock do
          settings.update!(collection_mode: form.collection_mode, tax_rate_bps: form.tax_rate_bps,
            grace_period_days: form.grace_period_days, trial_ending_notice_days: form.trial_ending_notice_days,
            dunning_schedule: form.parsed_dunning_schedule)
        end
        Billing::Result.new(status: :saved, record: settings, form: form)
      end
    end
  end
end
