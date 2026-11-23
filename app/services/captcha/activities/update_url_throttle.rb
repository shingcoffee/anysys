# frozen_string_literal: true

require "ostruct"

module Captcha
  module Activities
    class UpdateUrlThrottle
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)

      def self.call(match_kind:, url_pattern:, preset:, limit_count: nil, period_minutes: nil,
                    customer_id: nil, surface_key: nil, page: nil, skipped: nil)
        attrs = {
          match_kind: match_kind.to_s,
          url_pattern: url_pattern.to_s,
          preset: preset.to_s,
          limit_count: limit_count,
          period_minutes: period_minutes,
          customer_id: customer_id,
          surface_key: surface_key.to_s.presence,
          page: page,
          skipped: skipped
        }
        contract = Captcha::Contracts::UrlThrottle.new(OpenStruct.new)
        unless contract.validate(attrs)
          return Result.new(success?: false, model: nil, errors: contract.errors.full_messages)
        end

        resolved = Captcha::ThrottlePresets.resolve(
          attrs[:preset],
          limit_count: attrs[:limit_count],
          period_minutes: attrs[:period_minutes]
        )
        row = Captcha::UrlThrottle.find_or_initialize_by(
          match_kind: attrs[:match_kind],
          url_pattern: attrs[:url_pattern]
        )
        row.assign_attributes(
          limit_count: resolved[:limit_count],
          period_seconds: resolved[:period_seconds],
          every_hit: resolved[:every_hit],
          customer_id: customer_id,
          surface_key: attrs[:surface_key],
          page_id: page&.id
        )
        unless skipped.nil?
          row.skipped = ActiveModel::Type::Boolean.new.cast(skipped)
        end
        row.save!
        Captcha::ThrottleRegistry.bust!
        Result.new(success?: true, model: row, errors: [])
      rescue ActiveRecord::RecordNotUnique
        row = Captcha::UrlThrottle.find_by!(
          match_kind: attrs[:match_kind],
          url_pattern: attrs[:url_pattern]
        )
        row.assign_attributes(
          limit_count: resolved[:limit_count],
          period_seconds: resolved[:period_seconds],
          every_hit: resolved[:every_hit],
          customer_id: customer_id,
          surface_key: attrs[:surface_key],
          page_id: page&.id
        )
        unless skipped.nil?
          row.skipped = ActiveModel::Type::Boolean.new.cast(skipped)
        end
        row.save!
        Captcha::ThrottleRegistry.bust!
        Result.new(success?: true, model: row, errors: [])
      rescue ArgumentError, TypeError => e
        Result.new(success?: false, model: nil, errors: [e.message])
      end
    end
  end
end
