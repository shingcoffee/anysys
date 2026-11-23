# frozen_string_literal: true

module Emails
  class SendActivityBuilderComponent < ViewComponent::Base
    include Rails.application.routes.url_helpers

    STEPS = %w[audience content schedule review].freeze

    def initialize(send_activity:, templates:, lists:, url:, method:)
      @send_activity = send_activity
      @templates = templates
      @lists = lists
      @url = url
      @method = method
    end

    def step_label(key)
      I18n.t("admin_modules.emails.send_activities.wizard.steps.#{key}")
    end

    def submit_label
      @send_activity.persisted? ? I18n.t("common.actions.update") : I18n.t("common.actions.create")
    end

    def cancel_url
      cid = @send_activity.customer_id
      if @send_activity.persisted?
        admin_modules_emails_send_activity_path(cid, @send_activity)
      else
        admin_modules_emails_send_activities_path(cid)
      end
    end

    def lists_json_url
      admin_modules_emails_lists_path(@send_activity.customer_id, format: :json)
    end

    def templates_json_url
      admin_modules_emails_templates_path(@send_activity.customer_id, format: :json)
    end

    def new_list_url
      new_admin_modules_emails_list_path(@send_activity.customer_id)
    end

    def new_template_url
      new_admin_modules_emails_template_path(@send_activity.customer_id)
    end
  end
end
