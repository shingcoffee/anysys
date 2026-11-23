# frozen_string_literal: true

module Billing
  # Global singleton configuration for the billing module.
  # Accessed via `Billing::Settings.current` — creates the row with defaults
  # on first access (same pattern as Captcha::ProviderSettings.for_provider).
  class Settings < ApplicationRecord
    self.table_name = "billing_settings"

    COLLECTION_MODES = %w[manual gateway].freeze

    validates :collection_mode, inclusion: { in: COLLECTION_MODES }
    validates :tax_rate_bps, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000, only_integer: true }
    validates :grace_period_days,
              numericality: { greater_than_or_equal_to: 0, only_integer: true }
    validates :trial_ending_notice_days,
              numericality: { greater_than_or_equal_to: 0, only_integer: true }

    # Retrieve (or create) the single global settings row.
    # Uses a singleton_guard column with a unique index (value always 0) so that
    # concurrent processes performing find_or_create_by! never produce a second
    # row — the DB-level unique constraint turns the race into a harmless retry.
    def self.current
      find_or_create_by!(singleton_guard: 0) do |s|
        s.tax_rate_bps             = 0
        s.collection_mode          = "manual"
        s.grace_period_days        = 7
        s.trial_ending_notice_days = 3
        s.dunning_schedule         = [1, 3, 7]
      end
    end

    def manual?  = collection_mode == "manual"
    def gateway? = collection_mode == "gateway"

    def dunning_offsets
      Array(dunning_schedule)
    end

    def policy_snapshot
      attributes.slice("collection_mode", "tax_rate_bps", "grace_period_days").merge("dunning_schedule" => dunning_offsets.dup)
    end
  end
end
