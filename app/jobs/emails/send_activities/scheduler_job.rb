# frozen_string_literal: true

module Emails
  module SendActivities
    # Runs every minute (production). Delegates to Emails::SendActivities::StartSendActivity,
    # which atomically claims each due campaign (so two overlapping ticks never
    # double-send or double-create a recurring occurrence) and enqueues the send.
    # Cross-tenant by design (no Current.customer).
    class SchedulerJob < ApplicationJob
      queue_as :default

      def perform
        Emails::SendActivities::SendActivity.due_for_send.find_each do |campaign|
          Emails::SendActivities::StartSendActivity.call(campaign, due_only: true)
        end
      end
    end
  end
end
