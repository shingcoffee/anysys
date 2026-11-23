# frozen_string_literal: true

module JourneyRuns
  class PurgeJob < ApplicationJob
    queue_as :default

    def perform = JourneyRun.where("expires_at < ?", 7.days.ago).delete_all
  end
end
