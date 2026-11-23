# frozen_string_literal: true

module PlatformAnnouncements
  # Resolves the bell inbox for a tenant admin: live notices plus a 7-day
  # history of ended, unpublished-from-live, and discarded rows.
  #
  # Query-time inbox over platform_announcements — only read receipts are
  # persisted. Does not honour banner dismissals.
  class InboxResolver
    CANDIDATE_LIMIT = 50
    HISTORY_RETENTION = 7.days

    Result = Struct.new(:announcements, :read_ids, keyword_init: true)

    class << self
      def for_customer(customer_id, now: Time.current)
        Result.new(
          announcements: new(customer_id: customer_id, now: now).call,
          read_ids: []
        )
      end

      def for_viewer(user:, customer_id:, now: Time.current)
        result = for_customer(customer_id, now: now)
        result.read_ids = PlatformAnnouncementRead.announcement_ids_for(
          user_id: user&.id, customer_id: customer_id
        )
        result
      end
    end

    def initialize(customer_id:, now: Time.current)
      @customer_id = customer_id
      @now         = now
    end

    def call
      AudienceResolver.call(
        scope: PlatformAnnouncement.where(candidate_predicate), customer_id: customer_id, limit: CANDIDATE_LIMIT
      )
    end

    private

    attr_reader :customer_id, :now

    def candidate_predicate
      t = PlatformAnnouncement.arel_table
      retention = now - HISTORY_RETENTION

      live_window = t[:starts_at].eq(nil).or(t[:starts_at].lteq(now))
                     .and(t[:ends_at].eq(nil).or(t[:ends_at].gt(now)))
      live = t[:deleted_at].eq(nil).and(t[:status].eq("published")).and(live_window)

      left_recently = t[:left_live_at].gt(retention)

      ended_recently = t[:deleted_at].eq(nil)
                       .and(t[:status].eq("published"))
                       .and(t[:ends_at].gt(retention))
                       .and(t[:ends_at].lteq(now))

      live.or(left_recently).or(ended_recently)
    end
  end
end
