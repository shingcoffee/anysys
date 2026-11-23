# frozen_string_literal: true

module PlatformAnnouncements
  # Resolves which live announcements a tenant admin should currently see.
  #
  # Eligibility is evaluated in bounded batches before the display cap;
  # irrelevant tenants' notices cannot hide this tenant's critical notices.
  class Resolver
    # Maximum relevant notices returned, highest severity then newest first.
    CANDIDATE_LIMIT = 50

    class << self
      def for_customer(customer_id, dismissed_ids: [], now: Time.current)
        new(customer_id: customer_id, dismissed_ids: dismissed_ids, now: now).call
      end

      # Convenience for the banner: derives the dismissed set from the viewer.
      def for_viewer(user:, customer_id:, now: Time.current)
        dismissed = PlatformAnnouncementDismissal.announcement_ids_for(
          user_id: user&.id, customer_id: customer_id
        )
        for_customer(customer_id, dismissed_ids: dismissed, now: now)
      end
    end

    def initialize(customer_id:, dismissed_ids: [], now: Time.current)
      @customer_id   = customer_id
      @dismissed_ids = Array(dismissed_ids).compact_blank
      @now           = now
    end

    def call
      scope = PlatformAnnouncement.live(now)
      scope = scope.where.not(id: dismissed_ids) if dismissed_ids.any?
      AudienceResolver.call(scope: scope, customer_id: customer_id, limit: CANDIDATE_LIMIT, priority: true)
    end

    private

    attr_reader :customer_id, :dismissed_ids, :now
  end
end
