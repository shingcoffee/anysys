# frozen_string_literal: true

module Captcha
  module ThrottlePresets
    DEFAULT_LIMIT = 100
    DEFAULT_PERIOD = 5.minutes
    EVERY_HIT_GRANT = 5.minutes
    SETTINGS_CACHE_TTL = 60.seconds
    SNAPSHOT_TTL = 10.minutes
    MAX_FILE_BYTES = 5.megabytes
    MIN_CUSTOM_LIMIT = 1
    MAX_CUSTOM_LIMIT = 10_000
    MIN_CUSTOM_PERIOD_MINUTES = 1
    MAX_CUSTOM_PERIOD_MINUTES = 60

    PRESET_5_PER_1MIN = "5_per_1min"
    PRESET_20_PER_1MIN = "20_per_1min"
    PRESET_100_PER_5MIN = "100_per_5min"
    PRESET_EVERY_HIT = "every_hit"
    PRESET_CUSTOM = "custom"

    KEYS = [
      PRESET_5_PER_1MIN,
      PRESET_20_PER_1MIN,
      PRESET_100_PER_5MIN,
      PRESET_EVERY_HIT,
      PRESET_CUSTOM
    ].freeze

    module_function

    def default_rule
      { limit_count: DEFAULT_LIMIT, period_seconds: DEFAULT_PERIOD.to_i, every_hit: false }
    end

    def resolve(preset, limit_count: nil, period_minutes: nil)
      case preset.to_s
      when PRESET_5_PER_1MIN
        { limit_count: 5, period_seconds: 1.minute.to_i, every_hit: false }
      when PRESET_20_PER_1MIN
        { limit_count: 20, period_seconds: 1.minute.to_i, every_hit: false }
      when PRESET_100_PER_5MIN
        { limit_count: 100, period_seconds: 5.minutes.to_i, every_hit: false }
      when PRESET_EVERY_HIT
        { limit_count: nil, period_seconds: nil, every_hit: true }
      when PRESET_CUSTOM
        {
          limit_count: Integer(limit_count),
          period_seconds: Integer(period_minutes) * 60,
          every_hit: false
        }
      else
        default_rule
      end
    end

    def key_for(limit_count:, period_seconds:, every_hit:)
      return PRESET_EVERY_HIT if every_hit
      return PRESET_5_PER_1MIN if limit_count.to_i == 5 && period_seconds.to_i == 60
      return PRESET_20_PER_1MIN if limit_count.to_i == 20 && period_seconds.to_i == 60
      return PRESET_100_PER_5MIN if limit_count.to_i == 100 && period_seconds.to_i == 300

      PRESET_CUSTOM
    end
  end
end
