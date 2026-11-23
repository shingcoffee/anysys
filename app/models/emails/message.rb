# frozen_string_literal: true

module Emails
  class Message < ApplicationRecord
    self.table_name = "email_messages"

    include TenantScoped

    STATUSES          = %w[pending queued sent delivered bounced complained failed suppressed].freeze
    TERMINAL_STATUSES = %w[delivered bounced complained failed suppressed].freeze
    MESSAGE_TYPES     = %w[transactional campaign].freeze

    belongs_to :email_template, optional: true,
                                class_name: "Emails::Template",
                                foreign_key: :email_template_id

    has_many :message_events, class_name: "Emails::MessageEvent",
                              foreign_key: :message_id,
                              dependent: :destroy,
                              inverse_of: :message

    validates :customer_id,     presence: true
    validates :to,              presence: true
    validates :from,            presence: true
    validates :subject,         presence: true
    validates :body_html,       presence: true
    validates :status,          inclusion: { in: STATUSES }
    validates :message_type,    inclusion: { in: MESSAGE_TYPES }
    validates :idempotency_key, uniqueness: { scope: :customer_id }, allow_nil: true

    scope :non_terminal, -> { where.not(status: TERMINAL_STATUSES) }

    def terminal? = TERMINAL_STATUSES.include?(status)

    # Monotonic transitions: a message never regresses out of a terminal status,
    # and `delivered` is the success floor (a late failure/bounce never
    # overwrites a confirmed delivery).
    def mark_sent!(provider_message_id: nil, claim_token: nil)
      transition!(from: %w[pending queued], status: "sent", sent_at: Time.current,
                  provider_message_id: provider_message_id, claim_token: claim_token)
    end

    def mark_delivered!
      transition!(from: %w[pending queued sent], status: "delivered", delivered_at: Time.current)
    end

    def mark_bounced!(code:, message:)
      transition!(from: %w[pending queued sent], status: "bounced",
                  failure_code: clip_failure(code), failure_message: clip_failure(message))
    end

    # A complaint can legitimately arrive AFTER delivery (recipient marks spam),
    # so `delivered` is not a terminal barrier here — only an already-final
    # complaint/suppression/failure is.
    def mark_complained!(code: "complaint", message: nil)
      transition!(from: %w[pending queued sent delivered bounced], status: "complained",
                  failure_code: clip_failure(code), failure_message: clip_failure(message))
    end

    def mark_failed!(code:, message:, claim_token: nil)
      transition!(from: %w[pending queued], status: "failed",
                  failure_code: clip_failure(code), failure_message: clip_failure(message), claim_token: claim_token)
    end

    def mark_suppressed!(claim_token: nil)
      transition!(from: %w[pending queued], status: "suppressed", claim_token: claim_token)
    end

    def opens_count
      message_events.where(event_type: "open").count
    end

    def clicks_count
      message_events.where(event_type: "click").count
    end

    private

    # Conditional updates evaluate the current DB state, including when two
    # callbacks hold stale copies. A receipt may override delivered only when
    # it is a complaint. Dispatch ownership is cleared on terminal/send states.
    def transition!(from:, claim_token: nil, **attributes)
      scope = self.class.where(id: id, status: from)
      scope = scope.where(delivery_claim_token: claim_token == :unclaimed ? nil : claim_token) if claim_token
      scope.update_all(
        attributes.merge(delivery_claim_token: nil, delivery_claimed_at: nil, updated_at: Time.current)
      )
      reload
    end

    FAILURE_TEXT_LIMIT = 255

    def clip_failure(text)
      text.to_s.truncate(FAILURE_TEXT_LIMIT)
    end
  end
end
