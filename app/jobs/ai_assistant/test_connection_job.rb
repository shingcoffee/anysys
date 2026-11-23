# frozen_string_literal: true

module AiAssistant
  # Solid Queue job: refresh a provider's health (and Cursor's model list)
  # after a credentials save. The "Test connection" button runs the probe live.
  class TestConnectionJob < ApplicationJob
    queue_as :default

    def perform(settings_id)
      settings = AiAssistant::ProviderSettings.find_by(id: settings_id)
      return if settings.nil?

      AiAssistant::Activities::TestConnection.call(settings: settings)
    end
  end
end
