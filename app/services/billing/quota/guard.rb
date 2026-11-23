# frozen_string_literal: true

module Billing
  class Quota
    module Guard
      Result = Struct.new(:allowed, :item_key, :limit, :label, keyword_init: true) do
        def allowed? = allowed
        def message
          I18n.t("comp_billing.quota.limit_reached", limit: limit, label: label)
        end
      end

      def self.check(customer:, item_key:)
        q = Billing::Quota.for(customer)
        item = Billing::CountableItem.find_by(key: item_key.to_s)
        definition = Billing::Countable::Registry.find(item_key)
        allowed = definition ? q.allow?(item_key) : true
        Result.new(allowed: allowed, item_key: item_key.to_s,
                   limit: q.limit(item_key),
                    label: (definition&.default_label || item&.label))
      end
    end
  end
end
