# frozen_string_literal: true

module Sms
  module Admin
    class CampaignFormComponent < BaseComponent
      attr_reader :campaign
      STEPS = %w[audience content schedule review].freeze
      STEP_ERRORS = {
        "audience" => %i[name segment_id],
        "content" => %i[template_id variable_map variable_map_json],
        "schedule" => %i[send_timing scheduled_at scheduled_local timezone quiet_hours_start quiet_hours_end
                         frequency_window_hours send_rate_per_minute deadline_hours],
        "review" => []
      }.freeze

      def initialize(campaign:, templates:, segments:, contacts:, form_values:, preview:, errors:)
        @campaign, @templates, @segments, @contacts = campaign, templates, segments, contacts
        @form_values, @preview, @errors = form_values || {}, preview, errors || {}
      end

      def initial_step
        STEPS.each_with_index do |step, index|
          return index + 1 if STEP_ERRORS.fetch(step).any? { |key| field_error?(key) }
        end
        1
      end

      def first_step?
        initial_step == 1
      end

      def last_step?
        initial_step == STEPS.length
      end

      def step_state(number)
        return :done if number < initial_step
        return :current if number == initial_step

        :upcoming
      end

      def form_options
        multi_action_form_options(save_path, :sms_campaign).merge(
          class: "flex flex-col gap-6",
          data: {
            controller: "sms-campaign-wizard",
            turbo: false,
            sms_campaign_wizard_current_step_value: initial_step,
            sms_campaign_wizard_total_steps_value: STEPS.length,
            sms_campaign_wizard_field_required_msg_value: t("admin_modules.emails.send_activities.wizard.errors.field_required"),
            sms_campaign_wizard_send_now_label_value: t("sms_campaign_http.send_timing.immediate"),
            sms_campaign_wizard_em_dash_value: t("common.labels.em_dash"),
            sms_campaign_wizard_all_contacts_label_value: ui("campaigns.all_contacts")
          }
        )
      end

      def review_name
        form_value(:name).presence || t("common.labels.em_dash")
      end

      def review_audience
        id = form_value(:segment_id).to_s
        return ui("campaigns.all_contacts") if id.blank?

        @segments.find { |segment| segment[:id].to_s == id }&.dig(:name) || t("common.labels.em_dash")
      end

      def review_template
        selected_template&.dig(:label) || t("common.labels.em_dash")
      end

      def review_schedule
        if form_value(:send_timing, "immediate") == "scheduled" && form_value(:scheduled_local).present?
          form_value(:scheduled_local)
        else
          t("sms_campaign_http.send_timing.immediate")
        end
      end

      def scheduled?
        form_value(:send_timing, "immediate") == "scheduled"
      end

      def preview_path
        campaign.persisted? ? sms_path(:preview_campaign, campaign) : sms_path(:preview_campaigns)
      end

      def save_path
        campaign.persisted? ? sms_path(:campaign, campaign) : sms_path(:campaigns)
      end

      def mapping_example
        JSON.pretty_generate("name" => { "source" => "field", "field" => "name", "fallback" => t("common.labels.customer") },
                             "offer" => { "source" => "literal", "value" => "20%" },
                             "opt_out_url" => { "source" => "field", "field" => "unsubscribe_url" })
      end

      def selected_template
        @templates.find { |template| template[:id].to_s == form_value(:template_id).to_s }
      end

      private

      def field_error?(key)
        Array(@errors[key]).any? || Array(@errors[key.to_s]).any?
      end
    end
  end
end
