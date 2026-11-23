# frozen_string_literal: true

module Emails
  module SendActivities
    # Starts a campaign's send exactly once, atomically. Shared by the scheduler
    # (due campaigns) AND the manual "Send now" action so neither path can bypass
    # the atomic claim or the recurrence-scheduling that must accompany a send.
    # Returns true iff this call won the start.
    class StartSendActivity
      def self.call(send_activity, due_only: false)
        return false unless FeatureModules::Module.enabled?(key: "email", customer_id: send_activity.customer_id)

        started = false
        Quota.synchronize(send_activity.customer) do
          send_activity.lock!
          next unless send_activity.status == "pending"
          next if due_only && (send_activity.scheduled_at.nil? || send_activity.scheduled_at > Time.current)
          next unless ready_to_send?(send_activity)
          next unless SendActivity.claim!(send_activity.id)

          schedule_next_occurrence(send_activity) if send_activity.recurring?
          started = true
        end
        return false unless started

        ActiveSupport::Notifications.instrument("email_send_activity.lifecycle", event: "started", send_activity_id: send_activity.id)
        begin
          SendActivityJob.perform_later(send_activity.id)
        rescue StandardError => error
          # The processing ledger is recoverable by the existing campaign reaper.
          Rails.logger.warn("[email_send_activity.start] campaign=#{send_activity.id} #{error.class}: #{error.message}")
        end
        true
      end

      def self.ready_to_send?(send_activity)
        contract = Contracts::Build.new(Contracts::Build::Input.new)
        valid = contract.validate(customer_id: send_activity.customer_id, name: send_activity.name,
                                  email_template_id: send_activity.email_template_id, email_list_ids: send_activity.email_list_ids,
                                  scheduled_at: send_activity.scheduled_at, timezone: send_activity.timezone,
                                  recurrence_rule: send_activity.recurrence_rule)
        unless valid
          contract.errors.messages.each do |attribute, messages|
            Array(messages).each { |message| send_activity.errors.add(attribute, message) }
          end
        end
        valid
      end
      private_class_method :ready_to_send?

      def self.schedule_next_occurrence(send_activity)
        # Model validation rejects malformed rules at save time, but rescue
        # defensively so a legacy/hand-edited row can't take the send pipeline
        # down — it just stops recurring, same as an unsupported FREQ did before.
        rule = begin
          RecurrenceRule.parse(send_activity.recurrence_rule)
        rescue RecurrenceRule::Invalid
          nil
        end
        return unless rule

        # COUNT is "occurrences remaining starting from and including this send";
        # <= 1 means this was the last one in the series.
        count = rule["COUNT"]&.to_i
        return if count && count <= 1

        next_at = compute_next_occurrence(send_activity, rule)
        return unless next_at

        nxt = SendActivity.new(
          customer:        send_activity.customer,
          email_template:  send_activity.email_template,
          name:            send_activity.name,
          status:          "pending",
          scheduled_at:    next_at,
          recurrence_rule: count ? RecurrenceRule.with_count(send_activity.recurrence_rule, count - 1) : send_activity.recurrence_rule,
          timezone:        send_activity.timezone
        )
        nxt.email_lists = send_activity.email_lists.to_a
        nxt.save!
      end

      def self.compute_next_occurrence(send_activity, rule)
        interval = rule["INTERVAL"]&.to_i
        interval = 1 if interval.nil? || interval <= 0
        step = case rule["FREQ"]
        when "DAILY"   then interval.days
        when "WEEKLY"  then interval.weeks
        when "MONTHLY" then interval.months
        when "HOURLY"  then interval.hours
        end
        return nil unless step

        zone = send_activity.timezone.presence || "UTC"

        # Advance from the scheduled base, in the send activity's own timezone so DST
        # transitions don't drift the wall-clock send time, until strictly in the
        # future so a delayed run never emits an already-past occurrence
        # (catch-up storm).
        base    = (send_activity.scheduled_at || Time.current).in_time_zone(zone)
        next_at = base + step
        next_at += step while next_at <= Time.current

        if rule["UNTIL"]
          until_at = RecurrenceRule.parse_until(rule["UNTIL"], zone: zone)
          return nil if until_at && next_at > until_at
        end

        next_at
      end

      def self.timezone_preview(send_activity, limit: 5)
        return [] unless send_activity.recurring?

        rule = begin
          RecurrenceRule.parse(send_activity.recurrence_rule)
        rescue RecurrenceRule::Invalid
          nil
        end
        return [] unless rule

        occurrences = []
        current_base = (send_activity.scheduled_at || Time.current).in_time_zone(send_activity.timezone.presence || "UTC")
        count = rule["COUNT"]&.to_i

        limit = [limit, count].compact.min if count
        return [] if limit <= 0

        # Assuming current_base is the first intended occurrence, add it if future
        occurrences << current_base

        dummy = Struct.new(:scheduled_at, :timezone).new(current_base, send_activity.timezone)

        while occurrences.length < limit
          next_at = compute_next_occurrence_from_base(dummy.scheduled_at, send_activity.timezone, rule)
          break unless next_at

          occurrences << next_at
          dummy.scheduled_at = next_at
        end

        occurrences.take(limit)
      end

      def self.compute_next_occurrence_from_base(base_time, timezone, rule)
        interval = rule["INTERVAL"]&.to_i
        interval = 1 if interval.nil? || interval <= 0
        step = case rule["FREQ"]
        when "DAILY"   then interval.days
        when "WEEKLY"  then interval.weeks
        when "MONTHLY" then interval.months
        when "HOURLY"  then interval.hours
        end
        return nil unless step

        zone = timezone.presence || "UTC"
        base = base_time.in_time_zone(zone)
        next_at = base + step

        if rule["UNTIL"]
          until_at = RecurrenceRule.parse_until(rule["UNTIL"], zone: zone)
          return nil if until_at && next_at > until_at
        end

        next_at
      end
    end
  end
end
