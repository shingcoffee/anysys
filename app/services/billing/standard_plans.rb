# frozen_string_literal: true

module Billing
  module StandardPlans
    # Keys are stable data. Built-in presentation is resolved at command time.
    CATALOG = [
      { code: "free", amount_usd: "0", amount_cny: "0", trial_days: 0,
        limits: { "page" => 10, "entity" => 5, "member" => 1 } },
      { code: "starter-monthly", amount_usd: "29", amount_cny: "299", trial_days: 14,
        limits: { "page" => 50, "entity" => 25, "member" => 5 } },
      { code: "pro-monthly", amount_usd: "99", amount_cny: "999", trial_days: 14,
        limits: { "page" => 500, "entity" => 200, "member" => 25 } },
      { code: "enterprise-monthly", amount_usd: "499", amount_cny: "4999", trial_days: 14,
        limits: { "page" => -1, "entity" => -1, "member" => -1 } }
    ].freeze

    # Pure bootstrap capacity, not a paid enrollment or catalog seed. An
    # explicitly configured default (including finite zero) always takes priority.
    def self.starter_limits
      CATALOG.find { |offering| offering[:code] == "starter-monthly" }.fetch(:limits).dup.freeze
    end

    def self.seed!
      ApplicationRecord.transaction do
        Countable::CatalogSync.call
        CountableItem.where(key: Countable::Registry.keys).update_all(enabled: true)
        CATALOG.each_with_index do |attributes, position|
          # Explicit catalog edits/archives are authoritative; seeding never
          # rewrites a referenced offering or silently reopens an archive.
          next if Plan.exists?(code: attributes[:code])
          params = attributes.except(:limits).merge(interval: "monthly", active: true,
            is_default: position.zero? && !Plan.exists?(is_default: true), position: position + 1,
            name: I18n.t("comp_billing.standard_plans.#{attributes[:code]}.name"),
            description: I18n.t("comp_billing.standard_plans.#{attributes[:code]}.description"))
          result = Catalog::SavePlan.call(plan: Plan.new, params: params, limits: attributes[:limits])
          raise ActiveRecord::RecordInvalid.new(result.record) unless result.status == :saved
        end
      end
    end
  end
end
