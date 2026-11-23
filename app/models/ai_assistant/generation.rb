# frozen_string_literal: true

module AiAssistant
  class Generation < ApplicationRecord
    self.table_name = "ai_assistant_generations"

    include TenantScoped

    STATUSES = %w[queued running completed failed cancelled superseded].freeze
    ACTIVE_STATUSES = %w[queued running].freeze
    TERMINAL_STATUSES = (STATUSES - ACTIVE_STATUSES).freeze

    # A `running` row whose worker died (crash, deploy) never reaches a
    # terminal status on its own: the conversation keeps pointing at it and
    # every open tab keeps a half-written draft and a "Thinking…" pill. Past
    # this age the worker is presumed gone. Comfortably above the worst case a
    # live turn can take (AiAssistant::Limits::MAX_VENDOR_CALLS provider calls
    # at the provider's request deadline each, Cursor's AGENT_TIMEOUT being the
    # longest), so a slow turn is never stolen.
    MAX_RUNNING_AGE = 140.minutes

    # A `queued` row is only waiting on the job runner, so it gets a shorter
    # grace before it counts as an enqueue that never arrived.
    MAX_QUEUED_AGE = 10.minutes

    belongs_to :conversation, class_name: "AiAssistant::Conversation",
                              inverse_of: :generations
    belongs_to :user_message, class_name: "AiAssistant::Message"

    validates :customer_id, presence: true
    validates :token, presence: true, uniqueness: true
    validates :status, inclusion: { in: STATUSES }
    validate :user_message_matches_scope

    # Rows with nobody left to write to them.
    scope :stalled, -> {
      where(
        "(status = 'running' AND (started_at IS NULL OR started_at <= :running_cutoff)) OR " \
        "(status = 'queued' AND created_at <= :queued_cutoff)",
        running_cutoff: Time.current - MAX_RUNNING_AGE,
        queued_cutoff: Time.current - MAX_QUEUED_AGE
      )
    }

    # What a reply job may take over: a `queued` row, or a `running` one whose
    # worker is presumed gone. Without the second case a re-driven job finds
    # `running`, reports stale and exits, leaving the turn unattended for good.
    scope :claimable, -> {
      where(
        "status = 'queued' OR " \
        "(status = 'running' AND (started_at IS NULL OR started_at <= :cutoff))",
        cutoff: Time.current - MAX_RUNNING_AGE
      )
    }

    # Atomic conditional transition, mirroring
    # Emails::SendActivities::SendActivity.fail_stalled!: only the caller whose
    # UPDATE affects the row proceeds, so overlapping reconciler runs cannot
    # both terminalize it, and a row a live worker has just claimed (status or
    # started_at moved) is left alone. Returns true iff THIS call transitioned.
    def self.time_out!(id)
      now = Time.current
      stalled.where(id: id).update_all(
        status: "failed",
        failure_code: "timed_out",
        finished_at: now,
        updated_at: now
      ) == 1
    end

    private

    def user_message_matches_scope
      return if user_message.blank? || conversation.blank? || customer_id.blank?
      return if user_message.conversation_id == conversation_id &&
                user_message.customer_id == customer_id &&
                conversation.customer_id == customer_id

      errors.add(:user_message, :invalid)
    end
  end
end
