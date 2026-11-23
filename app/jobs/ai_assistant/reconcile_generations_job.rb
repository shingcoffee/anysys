# frozen_string_literal: true

module AiAssistant
  # Thin wrapper over AiAssistant::Cron::ReconcileGenerations, scheduled from
  # config/recurring.yml.
  class ReconcileGenerationsJob < ApplicationJob
    queue_as :default

    def perform
      AiAssistant::Cron::ReconcileGenerations.call
    end
  end
end
