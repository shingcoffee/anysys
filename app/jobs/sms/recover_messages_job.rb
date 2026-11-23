# frozen_string_literal: true

module Sms
  class RecoverMessagesJob < ApplicationJob
    queue_as :default

    def perform
      Cron::RecoverMessages.call
    end
  end
end
