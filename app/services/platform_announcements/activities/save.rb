# frozen_string_literal: true

module PlatformAnnouncements
  module Activities
    class Save
      Result = Struct.new(:success?, :model, :errors, :messages, keyword_init: true)

      ATTRIBUTES = %i[
        title body_en body_zh severity link_url status audience starts_at ends_at target_rules
      ].freeze

      NULLABLE = %i[link_url starts_at ends_at].freeze

      def self.call(record:, params:)
        was_live = record.persisted? && record.live?
        previous_users = was_live ? Notifications::Stream.announcement_recipients(record).to_a : []
        attributes = sanitize(params)
        record.assign_attributes(attributes.slice(*ATTRIBUTES))

        contract = PlatformAnnouncements::Contracts::Announcement.new(record)
        unless contract.validate(attributes)
          return Result.new(success?: false, model: record,
                            errors: contract.errors.messages.to_h, messages: contract.errors.full_messages)
        end

        persist!(record, contract, was_live: was_live)
        Notifications::Stream.sync_announcement!(record, previous_users: previous_users)
        Result.new(success?: true, model: record, errors: {}, messages: [])
      end

      # Normalizes the raw form payload:
      #   * blank optionals collapse to nil rather than ""
      #   * the audience builder's JSON string becomes a rules Hash
      #   * an "all customers" announcement never keeps stale segment rules
      def self.sanitize(params)
        attributes = params.to_h.symbolize_keys
        NULLABLE.each { |key| attributes[key] = attributes[key].presence if attributes.key?(key) }

        target_rules = resolve_target_rules(attributes)
        attributes[:target_rules_malformed] = target_rules.malformed?
        attributes[:target_rules] =
          if attributes[:audience].to_s == "selected" || target_rules.malformed?
            target_rules.rules
          else
            TargetRules::EMPTY
          end
        attributes
      end
      private_class_method :sanitize

      def self.resolve_target_rules(attributes)
        raw = attributes.delete(:target_rules_json)
        return TargetRules.parse(raw) unless raw.nil?

        TargetRules.parse(attributes[:target_rules])
      end
      private_class_method :resolve_target_rules

      def self.persist!(record, contract, was_live:)
        record.target_rules =
          record.audience == "selected" ? (contract.target_rules.presence || TargetRules::EMPTY) : TargetRules::EMPTY
        if record.live? || record.scheduled?
          record.left_live_at = nil
        elsif was_live
          record.left_live_at ||= Time.current
        end
        record.save!
      end
      private_class_method :persist!
    end
  end
end
