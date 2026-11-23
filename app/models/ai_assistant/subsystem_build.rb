# frozen_string_literal: true

module AiAssistant
  # One background build of a sub-system the assistant started in a
  # conversation from a requirements brief: the domain, the business flows,
  # the entities fitted to them, a page per journey step, the processing for
  # those pages, the bindings and the launch. It runs in
  # AiAssistant::SubsystemBuildJob from the stored stage, pauses with
  # questions for the admin (and once for the platform owner's review of the
  # flows), and resumes when they answer.
  class SubsystemBuild < ApplicationRecord
    self.table_name = "ai_assistant_subsystem_builds"

    include TenantScoped

    STATUSES = %w[running waiting_for_answers finished failed cancelled].freeze
    ACTIVE_STATUSES = %w[running waiting_for_answers].freeze
    STAGES = %w[domain journeys review entities pages processing binding launch report].freeze

    # A running build saves after every item, so one untouched this long has
    # lost its worker (crash, deploy) and would otherwise hold the
    # conversation's single active slot for good.
    MAX_RUNNING_AGE = AiAssistant::Generation::MAX_RUNNING_AGE

    belongs_to :conversation, class_name: "AiAssistant::Conversation"
    belongs_to :user, class_name: "Authentication::User"

    validates :customer_id, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :stage, inclusion: { in: STAGES }
    validate :conversation_matches_tenant

    scope :active, -> { where(status: ACTIVE_STATUSES) }

    def active? = ACTIVE_STATUSES.include?(status)
    def running? = status == "running"
    def waiting_for_answers? = status == "waiting_for_answers"
    def cancelled? = status == "cancelled"

    def stalled?
      running? && updated_at.present? && updated_at <= MAX_RUNNING_AGE.ago
    end

    def name = blueprint_json["domain"].to_s
    def brief = AiAssistant::Subsystems::Brief.new(blueprint_json["brief"])

    def blueprint_json = blueprint.is_a?(Hash) ? blueprint : {}
    def results_json = results.is_a?(Hash) ? results : {}

    private

    def conversation_matches_tenant
      return if conversation.nil? || conversation.customer_id == customer_id

      errors.add(:conversation, :invalid)
    end
  end
end
