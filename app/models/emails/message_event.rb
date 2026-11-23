# frozen_string_literal: true

module Emails
  class MessageEvent < ApplicationRecord
    self.table_name = "email_message_events"

    belongs_to :message, class_name: "Emails::Message"

    validates :event_type, presence: true, inclusion: { in: %w[open click] }
    validates :occurred_at, presence: true

    class << self
      def record_open!(message, request:)
        return if where(message_id: message.id, event_type: "open").exists?

        create!(
          message: message,
          event_type: "open",
          ip: request.remote_ip,
          user_agent: clip_attr(request.user_agent),
          occurred_at: Time.current
        )
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      def record_click!(message, url:, request:)
        create!(
          message: message,
          event_type: "click",
          url: clip_attr(url),
          ip: request.remote_ip,
          user_agent: clip_attr(request.user_agent),
          occurred_at: Time.current
        )
      end

      ATTR_LIMIT = 255

      def clip_attr(value)
        value.to_s.truncate(ATTR_LIMIT)
      end
      private :clip_attr
    end
  end
end
