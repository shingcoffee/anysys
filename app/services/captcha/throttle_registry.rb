# frozen_string_literal: true

module Captcha
  # Cached throttle rows + public-page UUID index. TTL is
  # Captcha::ThrottlePresets::SETTINGS_CACHE_TTL.
  class ThrottleRegistry
    CACHE_KEY = "captcha/url_throttles/v2"
    PAGE_INDEX_KEY = "captcha/url_throttles/pages"

    Record = Data.define(
      :match_kind, :url_pattern, :limit_count, :period_seconds, :every_hit, :skipped, :surface_key, :page_id, :customer_id
    ) do
      def preset_key
        Captcha::ThrottlePresets.key_for(
          limit_count: limit_count,
          period_seconds: period_seconds,
          every_hit: every_hit
        )
      end

      def period_minutes
        return nil if period_seconds.blank?

        period_seconds / 60
      end
    end

    Rule = Data.define(
      :pattern, :match_kind, :limit_count, :period_seconds, :every_hit, :skipped, :fail_closed, :surface_key, :page_id
    ) do
      def skipped? = skipped == true
    end

    class << self
      def rules
        fetch(CACHE_KEY) { Captcha::UrlThrottle.all.map { |row| record_from(row) } }
      end

      def page_index
        fetch(PAGE_INDEX_KEY) { build_page_index }
      end

      def display_for(match_kind:, url_pattern:)
        row = Array(rules).find { |record| record.match_kind == match_kind && record.url_pattern == url_pattern }
        defaults = Captcha::ThrottlePresets.default_rule
        {
          preset: row ? row.preset_key : Captcha::ThrottlePresets::PRESET_100_PER_5MIN,
          limit_count: row&.limit_count || defaults[:limit_count],
          period_minutes: row&.period_minutes || (defaults[:period_seconds] / 60),
          skipped: row&.skipped == true
        }
      end

      def bust!
        store.delete(CACHE_KEY)
        store.delete(PAGE_INDEX_KEY)
      end

      def store
        @store ||= if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
                     ActiveSupport::Cache::MemoryStore.new
        else
                     Rails.cache
        end
      end

      def reset_store!
        @store = nil
      end

      private

      def record_from(row)
        Record.new(
          match_kind: row.match_kind,
          url_pattern: row.url_pattern,
          limit_count: row.limit_count,
          period_seconds: row.period_seconds,
          every_hit: row.every_hit,
          skipped: row.skipped == true,
          surface_key: row.surface_key,
          page_id: row.page_id,
          customer_id: row.customer_id
        )
      end

      def fetch(key, &block)
        store.fetch(key, expires_in: Captcha::ThrottlePresets::SETTINGS_CACHE_TTL, &block)
      end

      def build_page_index
        Page.for_audience("public").pluck(:id, :public_uuid, :customer_id, :launched).each_with_object({}) do |(id, uuid, customer_id, launched), index|
          index[uuid.to_s] = {
            "id" => id,
            "customer_id" => customer_id,
            "shared" => customer_id.nil?,
            "launched" => launched
          }
        end
      end
    end
  end
end
