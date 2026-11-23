# frozen_string_literal: true

module AiAssistant
  # One chat thread for an admin user within a tenant. A user keeps a list of
  # them: the workspace opens the most recently active thread, and "New chat"
  # starts another rather than destroying the only one that exists.
  class Conversation < ApplicationRecord
    self.table_name = "ai_assistant_conversations"

    include TenantScoped

    belongs_to :user, class_name: "Authentication::User"
    has_many :messages, class_name: "AiAssistant::Message", dependent: :destroy,
             inverse_of: :conversation
    has_many :generations, class_name: "AiAssistant::Generation", dependent: :destroy,
             inverse_of: :conversation
    has_many :subsystem_builds, class_name: "AiAssistant::SubsystemBuild", dependent: :destroy
    belongs_to :current_generation, class_name: "AiAssistant::Generation", optional: true

    ARTIFACT_KINDS = AiAssistant::Assistant::Artifact::KINDS

    # A sidebar row has to stay readable at ~14rem, and the title is derived
    # from a prompt that may be paragraphs long.
    TITLE_LIMIT = 60

    # How many threads one user may keep per tenant. Without a ceiling the
    # sidebar (and the per-user row count) grows without bound.
    MAX_PER_USER = 50

    # How many archived threads any listing surfaces. The archived list is a
    # recovery aid, not a browsable history, and the sidebar and the JSON
    # endpoint have to agree on the number.
    ARCHIVED_LIMIT = 20

    validates :customer_id, presence: true
    validates :user_id, presence: true
    validates :title, length: { maximum: TITLE_LIMIT }, allow_nil: true
    validates :artifact_kind, inclusion: { in: ARTIFACT_KINDS }, allow_nil: true

    scope :active, -> { where(archived_at: nil) }
    scope :archived, -> { where.not(archived_at: nil) }
    # id breaks the tie when two threads share a timestamp, so paging and the
    # "current thread" lookup are deterministic.
    scope :recent_first, -> { order(last_active_at: :desc, id: :desc) }

    before_create :stamp_initial_activity

    class << self
      def owned_by(customer:, user:)
        where(customer: customer, user: user)
      end

      # The thread the workspace opens by default: the most recently active
      # unarchived one, created on demand for a user who has never chatted.
      def current_for(customer:, user:)
        user.with_lock do
          scope = owned_by(customer: customer, user: user)
          scope.active.recent_first.first ||
            reopen_latest(scope) ||
            start_for(customer: customer, user: user)
        end
      end

      # Resolves the thread a request names, refusing anything outside the
      # caller's own (customer, user) pair. A blank id means "the current one",
      # which is what an unscoped composer POST sends.
      def resolve(customer:, user:, id:)
        return current_for(customer: customer, user: user) if id.blank?

        owned_by(customer: customer, user: user).find_by(id: id)
      end

      def start_for(customer:, user:)
        user.with_lock do
          return nil if at_capacity?(customer: customer, user: user)

          create!(customer: customer, user: user)
        end
      end

      def at_capacity?(customer:, user:)
        owned_by(customer: customer, user: user).count >= MAX_PER_USER
      end

      private

      # This runs from a GET, so it must not mint a row the ceiling forbids:
      # archiving the last active thread and reloading would otherwise walk the
      # count past MAX_PER_USER without limit. At the ceiling the most recently
      # active archived thread is reopened instead — it becomes the current
      # thread, so leaving it archived would hide the page's own transcript.
      def reopen_latest(scope)
        return nil unless scope.count >= MAX_PER_USER

        scope.archived.recent_first.first&.tap(&:unarchive!)
      end
    end

    # Rounds already spent in this thread. What that number is allowed to be is
    # AiAssistant::Limits' business, not the row's.
    def user_turns
      messages.where(role: "user").count
    end

    def archived?
      archived_at.present?
    end

    def empty?
      messages.empty?
    end

    # Shown in the sidebar. An untitled thread borrows its first prompt, so a
    # thread is recognisable before anyone renames it.
    def display_title
      title.presence || fallback_title.presence || I18n.t("ai_assistant.assistant.conversations.untitled")
    end

    attr_writer :fallback_title

    def fallback_title
      @fallback_title ||= derived_title
    end

    # Resolves the borrowed titles for a whole list in two queries instead of
    # one per row. The sidebar is re-rendered on every message send, not just
    # on page load, so the per-row lookup was paid far more often than it read.
    def self.preload_fallback_titles(conversations)
      untitled = conversations.reject { |row| row.title.present? }
      return conversations if untitled.empty?

      first_ids = AiAssistant::Message.where(conversation_id: untitled.map(&:id), role: "user")
                                      .group(:conversation_id).minimum(:id)
      bodies = AiAssistant::Message.where(id: first_ids.values).pluck(:id, :body).to_h
      untitled.each { |row| row.fallback_title = truncate_title(bodies[first_ids[row.id]]) }

      conversations
    end

    # Called once the first user turn lands: a thread named after its opening
    # prompt is far easier to find later than "New chat (3)". A thread the user
    # renamed keeps its name.
    def adopt_title_from(text)
      return if title.present?

      candidate = self.class.truncate_title(text)
      return if candidate.blank?

      update_columns(title: candidate, updated_at: Time.current)
    end

    # Shared with Contracts::ConversationTitle so a typed title and a borrowed
    # one are normalised by the same rule.
    def self.collapse_whitespace(text)
      text.to_s.gsub(/\s+/, " ").strip
    end

    def self.truncate_title(text)
      collapsed = collapse_whitespace(text)
      return "" if collapsed.blank?
      return collapsed if collapsed.length <= TITLE_LIMIT

      "#{collapsed[0, TITLE_LIMIT - 1].rstrip}…"
    end

    # Bumps the sidebar ordering without touching the AR callback chain, so it
    # is safe to call from inside the reply job's write guard.
    def touch_activity!
      now = Time.current
      update_columns(last_active_at: now, updated_at: now)
    end

    def archive!
      touch_archived(Time.current)
    end

    def unarchive!
      touch_archived(nil)
    end

    private

    def derived_title
      first_prompt = messages.where(role: "user").order(:id).limit(1).pick(:body)
      self.class.truncate_title(first_prompt)
    end

    def touch_archived(value)
      now = Time.current
      update_columns(archived_at: value, updated_at: now)
    end

    def stamp_initial_activity
      self.last_active_at ||= Time.current
    end
  end
end
