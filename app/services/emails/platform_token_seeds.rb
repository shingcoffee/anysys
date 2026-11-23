# frozen_string_literal: true

module Emails
  # Idempotent platform catalog rows. Migration inserts them once; tests and
  # `db:seed` call `.ensure!` because schema loads do not replay data inserts.
  # UUIDs come from SecureRandom.uuid (via TemplateToken#assign_uuid).
  class PlatformTokenSeeds
    ROWS = [
      { source_key: "unsubscribe_url", label: "unsubscribe_url" }
    ].freeze

    def self.ensure!
      ROWS.each do |row|
        TemplateToken.find_or_create_by!(
          source_type: TemplateToken::SOURCE_PLATFORM,
          source_key: row[:source_key]
        ) do |token|
          token.customer_id = nil
          token.label = row[:label]
          token.entity_id = nil
          token.attribute_slug = nil
          # uuid left blank → TemplateToken#assign_uuid uses SecureRandom.uuid
        end
      end
    end
  end
end
