# frozen_string_literal: true

module Emails
  module SendActivities
    # Thin wrapper over Emails::SendActivities::Cron::ReconcileSendActivities, scheduled from
    # config/recurring.yml.
    class ReconcileSendActivitiesJob < ApplicationJob
      queue_as :default

      def perform
        Emails::SendActivities::Cron::ReconcileSendActivities.call
      end
    end
  end
end
