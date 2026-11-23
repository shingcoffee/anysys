# frozen_string_literal: true

module Sms
  module Admin
    class BaseComponent < ApplicationComponent
      STATUS_TONES = {
        "granted" => :success, "delivered" => :success, "completed" => :success,
        "active" => :success, "scheduled" => :info, "running" => :info,
        "sent" => :info, "admitted" => :info, "revoked" => :warning,
        "archived" => :warning, "skipped" => :warning, "suppressed" => :warning,
        "expired" => :warning, "failed" => :danger
      }.freeze

      # Field identifiers and enum values are protocol data; their labels reuse
      # paired translations and are resolved in the current locale at render time.
      LABEL_KEYS = {
        fields: {
          "name" => "common.labels.name", "phone" => "sms_audience.fields.phone_e164",
          "country_code" => "sms_audience.fields.country_code", "timezone" => "common.labels.timezone",
          "status" => "sms_audience.fields.status", "action" => "common.labels.action",
          "description" => "common.labels.description", "entity_id" => "common.labels.entity",
          "notes" => "common.labels.notes"
        },
        statuses: {
          "active" => "common.status.active", "archived" => "common.status.retired",
          "unknown" => "common.status.unknown", "granted" => "sms_campaign_http.consent_status.granted",
          "revoked" => "sms_campaign_http.consent_status.revoked", "draft" => "common.status.draft",
          "scheduled" => "common.status.scheduled", "running" => "sms_campaign_http.campaign_status.running",
          "completed" => "sms_campaign_http.campaign_status.completed", "cancelled" => "common.status.cancelled",
          "failed" => "common.status.failed", "pending" => "common.status.pending",
          "admitted" => "sms_campaign_http.recipient_status.admitted", "skipped" => "sms_campaign_http.recipient_status.skipped",
          "queued" => "common.status.queued", "delivered" => "common.status.delivered",
          "suppressed" => "common.status.suppressed", "expired" => "sms.statuses.expired"
        },
        sources: {
          "manual" => "sms_campaign_http.source_kind.manual", "entity" => "common.labels.entity",
          "admin" => "settings_people.admin_name"
        },
        nav: {
          "campaigns" => "sms_campaign_http.navigation.campaigns", "contacts" => "sms_campaign_http.navigation.contacts",
          "segments" => "admin_modules.emails.segments.index.title", "messages" => "admin_modules.nav.messages",
          "opt_outs" => "admin_modules.sms.opt_outs.title"
        },
        "campaigns.steps": {
          "audience" => "common.labels.audience", "content" => "admin_modules.emails.send_activities.wizard.steps.content",
          "schedule" => "admin_modules.emails.send_activities.wizard.steps.schedule", "review" => "admin_modules.emails.send_activities.wizard.steps.review"
        },
        campaigns: {
          "send_now" => "sms_campaign_http.send_timing.immediate", "cancelled_at" => "billing_mailer.subscription_cancelled.label_cancelled_at"
        },
        metrics: {
          "pending_count" => "common.status.pending", "admitted_count" => "sms_campaign_http.recipient_status.admitted",
          "api_accepted_count" => "sms_campaign_ui.statuses.sent", "delivered_count" => "common.status.delivered",
          "failed_count" => "common.status.failed", "unknown_count" => "common.status.unknown",
          "queued_count" => "common.status.queued", "suppressed_count" => "common.status.suppressed",
          "expired_count" => "sms.statuses.expired", "skipped_count" => "sms_campaign_http.recipient_status.skipped",
          "cancelled_count" => "common.status.cancelled"
        },
        entity_sync: {
          "created" => "common.status.created", "updated" => "common.labels.updated_at",
          "contact_id" => "chrome.customer_card.contact", "error_code" => "admin_modules.sms.opt_outs.reason"
        },
        sync_outcomes: {
          "created" => "common.status.created", "updated" => "common.labels.updated_at",
          "unchanged" => "sms_campaign_ui.entity_sync.unchanged", "invalid" => "sms_campaign_ui.entity_sync.invalid",
          "conflict" => "maint_core.pages.editor.save_conflict_label", "conflicts" => "maint_core.pages.editor.save_conflict_label"
        },
        encodings: {
          "gsm_7" => "sms_campaign_ui.encodings.gsm7", "ucs_2" => "sms_campaign_ui.encodings.ucs2"
        },
        reasons: {
          "phone_invalid" => "sms_standards.errors.invalid_phone", "invalid_phone" => "sms_standards.errors.invalid_phone",
          "no_eligible_contacts" => "sms_campaign_ui.reasons.audience_empty", "scheduled_at_required" => "sms_campaign_ui.reasons.schedule_required"
        }
      }.transform_values(&:freeze).freeze

      def customer_id
        helpers.current_customer_id
      end

      def sms_path(name, *args, **options)
        helpers.public_send("admin_modules_sms_#{name}_path", customer_id, *args, **options)
      end

      def ui(key, **options)
        t("sms_campaign_ui.#{key}", **options)
      end

      def label_text(group, name, **options)
        key = LABEL_KEYS.fetch(group.to_sym, {}).fetch(name.to_s) { "sms_campaign_ui.#{group}.#{name}" }
        t(key, **options)
      end

      def status_badge(status)
        render(BadgeComponent.new(variant: STATUS_TONES.fetch(status.to_s, :default))) { label_text(:statuses, status) }
      end

      def reason_label(reason)
        label_text(:reasons, reason, default: t("page_shortcuts.unavailable"))
      end

      def time_value(value)
        return t("sms_presentation.not_recorded") if value.blank?

        time = value.respond_to?(:iso8601) ? value : Time.iso8601(value.to_s)
        tag.time(I18n.l(time, format: :long), datetime: time.iso8601)
      rescue ArgumentError
        t("sms_presentation.not_recorded")
      end

      def fact(label, value)
        tag.div(class: "min-w-0") do
          safe_join([tag.dt(label, class: "form-label"),
                     tag.dd(value, class: "mt-1 break-words text-text-primary [overflow-wrap:anywhere]")])
        end
      end

      def form_value(key, default = nil)
        @form_values.fetch(key, default)
      end

      def field(form, key, type: :text, options: [], help: nil, **attributes)
        render FieldComponent.new(form: form, field: key, value: form_value(key),
                                  label: label_text(:fields, key), type: type, options: options,
                                  help: help, errors: @errors, attributes: attributes)
      end

      def section(title, id: nil, &block)
        render(SectionComponent.new(title: title, id: id), &block)
      end

      def error_summary(root:)
        render ErrorsComponent.new(errors: @errors, root: root)
      end

      def multi_action_form_options(url, scope)
        { url: url, scope: scope, method: :post, local: true,
          authenticity_token: helpers.form_authenticity_token,
          data: { turbo: false }, class: "space-y-6 min-w-0" }
      end
    end
  end
end
