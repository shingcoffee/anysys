# frozen_string_literal: true

module Emails
  module SendActivities
    # Validates and persists a send activity in one shot (wizard fields are
    # collected client-side; only the final Review submit hits the server).
    class Build
      STEPS = %w[audience content schedule review].freeze

      def self.call(send_activity, params)
        new(send_activity, params).call
      end

      def initialize(send_activity, params)
        @send_activity = send_activity
        @params = params
      end

      def call
        attrs = permitted_attributes
        list_ids = attrs.delete(:email_list_ids)
        saved = false
        Quota.synchronize(@send_activity.customer) do
          @send_activity.lock! if @send_activity.persisted?
          unless @send_activity.status == "pending"
            @send_activity.errors.add(:base, I18n.t("admin_modules.flash.send_activities.edit_status_blocked", status: @send_activity.status_label))
            next
          end
          @send_activity.assign_attributes(attrs)
          @parameter_errors.to_a.each { |message| @send_activity.errors.add(:base, message) }
          next if @send_activity.errors.any?

          contract = Contracts::Build.new(Contracts::Build::Input.new)
          valid = contract.validate(
            customer_id: @send_activity.customer_id, name: @send_activity.name,
            email_template_id: @send_activity.email_template_id,
            email_list_ids: list_ids || @send_activity.email_list_ids,
            scheduled_at: @send_activity.scheduled_at, timezone: @send_activity.timezone,
            recurrence_rule: @send_activity.recurrence_rule
          )
          unless valid
            contract.errors.messages.each do |attribute, messages|
              Array(messages).each { |message| @send_activity.errors.add(attribute, message) }
            end
            next
          end

          @send_activity.email_lists = contract.lists
          raise ActiveRecord::Rollback unless @send_activity.save

          saved = true
        end
        maybe_start! if saved
        { success: saved, send_activity: @send_activity }
      rescue ActiveRecord::RecordInvalid => error
        @send_activity.errors.merge!(error.record.errors)
        { success: false, send_activity: @send_activity }
      end

      private

      def permitted_attributes
        campaign_params = @params.require(:email_send_activity)
        permitted = campaign_params.permit(
          :name, :email_template_id,
          :scheduled_at, :recurrence_preset, :timezone, :send_timing,
          email_list_ids: []
        )
        send_timing = permitted.delete(:send_timing).to_s
        map_recurrence_preset!(permitted) if campaign_params.key?(:recurrence_preset)

        if send_timing == "now"
          zone_name = permitted[:timezone].presence || @send_activity.timezone.presence || "UTC"
          zone = ActiveSupport::TimeZone[zone_name] || ActiveSupport::TimeZone["UTC"]
          permitted[:scheduled_at] = zone.now
        elsif permitted[:scheduled_at].present?
          permitted[:scheduled_at] = parse_scheduled_at(permitted[:scheduled_at], permitted[:timezone])
        end

        permitted[:status] = "pending" if @send_activity.new_record?
        permitted
      end

      def maybe_start!
        return unless @send_activity.status == "pending"
        return if @send_activity.scheduled_at.blank?
        return if @send_activity.scheduled_at > Time.current

        StartSendActivity.call(@send_activity, due_only: true)
      end

      def map_recurrence_preset!(attributes)
        preset = attributes.delete(:recurrence_preset).to_s
        unless RecurrencePresets::PRESETS.key?(preset)
          @parameter_errors = [I18n.t("admin_modules.emails.send_activities.wizard.invalid_recurrence_preset")]
          return
        end

        attributes[:recurrence_rule] = RecurrencePresets.rrule_for(preset)
      end

      # `datetime_local_field` posts a naive wall-clock string (e.g. "2026-07-20T09:00")
      # with no offset. Interpret it in the campaign's timezone rather than the app
      # default zone, so the stored UTC instant matches what the admin actually typed.
      def parse_scheduled_at(raw_value, submitted_timezone)
        zone_name = submitted_timezone.presence || @send_activity&.timezone.presence || "UTC"
        zone = ActiveSupport::TimeZone[zone_name] || ActiveSupport::TimeZone["UTC"]
        zone.parse(raw_value) || raw_value
      rescue ArgumentError, TypeError
        raw_value
      end
    end
  end
end
