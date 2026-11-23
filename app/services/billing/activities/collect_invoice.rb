# frozen_string_literal: true

module Billing
  module Activities
    class CollectInvoice
      def self.call(invoice:, trigger: :initial, at: Time.current)
        Billing::Collector.collect(invoice, trigger: trigger, at: at)
      end
    end
  end
end
