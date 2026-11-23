# frozen_string_literal: true

module Sms
  module Campaigns
    class RunJob < ApplicationJob
      queue_as :default

      def perform(customer_id, campaign_id, run_token)
        customer = Customer.find_by(id: customer_id)
        campaign = Sms::Campaign.find_by(customer_id: customer_id, id: campaign_id)
        return unless customer && campaign
        Current.set(customer: customer) do
          outcome = Run.call(customer: customer, campaign: campaign, run_token: run_token)
          if outcome[:has_more] && outcome[:next_run_at]
            # Queued core work has its own accelerator; avoid a busy campaign
            # loop while delivery jobs compete for the account clock.
            due = [outcome[:next_run_at], Time.current + 1.second].max
            Support.enqueue(customer_id, campaign_id, run_token, due_at: due)
          end
        end
      end
    end
  end
end
