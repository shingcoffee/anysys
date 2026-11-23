# frozen_string_literal: true

module AiAssistant
  class Message < ApplicationRecord
    self.table_name = "ai_assistant_messages"

    include TenantScoped

    ROLES = %w[user assistant].freeze
    STATUSES = %w[complete failed cancelled].freeze

    belongs_to :conversation, class_name: "AiAssistant::Conversation", inverse_of: :messages
    has_many_attached :images

    # Messages carrying a proposal the admin has neither applied nor had
    # superseded. At most one per conversation: ReplyWriter retires the older
    # ones when it parks a new proposal, which is what lets PendingConfirmation
    # treat "the live proposal" as a single row.
    #
    # A JSON key test, not a LIKE on the serialized column: a proposal's own
    # document can contain the words of the key (an entity described as
    # "pending_confirmation" does it), and a substring scan would match the
    # consumed message it is stored on.
    scope :with_pending_proposal, -> { where("json_extract(metadata, '$.pending_confirmation') IS NOT NULL") }

    validates :customer_id, presence: true
    validates :role, inclusion: { in: ROLES }
    validates :body, presence: true
    validates :status, inclusion: { in: STATUSES }

    def metadata_json
      value = metadata
      value.is_a?(Hash) ? value : {}
    end

    def user?      = role == "user"
    def assistant? = role == "assistant"
  end
end
