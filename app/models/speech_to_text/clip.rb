# frozen_string_literal: true

module SpeechToText
  # Ephemeral job-handoff row for one dictation upload. Audio is purged when
  # Transcribe finishes; the row is kept (status + error_code) so the desktop
  # client can poll, then PruneClipsJob deletes it 15 minutes after completion.
  class Clip < ApplicationRecord
    self.table_name = "speech_to_text_clips"

    include TenantScoped

    STATUSES = %w[pending processing succeeded failed].freeze
    TERMINAL_STATUSES = %w[succeeded failed].freeze

    # Where the finished transcript goes. Recorded at enqueue time so the
    # transcribe job never has to infer intent from the field's DOM id:
    #
    #   "field"     — write the transcript into the element named by
    #                 field_dom_id (the reusable DictateFieldComponent)
    #   "assistant" — send the transcript to the AI assistant as a user turn
    #                 (the dashboard composer and the desktop client)
    DESTINATION_FIELD     = "field"
    DESTINATION_ASSISTANT = "assistant"
    DESTINATIONS          = [ DESTINATION_FIELD, DESTINATION_ASSISTANT ].freeze
    DEFAULT_DESTINATION   = DESTINATION_FIELD

    belongs_to :user, class_name: "Authentication::User"
    belongs_to :conversation, class_name: "AiAssistant::Conversation", optional: true
    has_one_attached :audio

    validates :customer_id, presence: true
    validates :field_dom_id, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :destination, inclusion: { in: DESTINATIONS }

    scope :pending, -> { where(status: "pending") }

    # Fails closed to "field": filling the caller's own input is harmless,
    # whereas defaulting to "assistant" would post a user's dictation into
    # their assistant conversation.
    def self.normalize_destination(value)
      candidate = value.to_s.strip
      DESTINATIONS.include?(candidate) ? candidate : DEFAULT_DESTINATION
    end

    def assistant? = destination == DESTINATION_ASSISTANT
    def field?     = destination == DESTINATION_FIELD
    def terminal?  = TERMINAL_STATUSES.include?(status)
  end
end
