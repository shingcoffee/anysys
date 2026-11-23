# frozen_string_literal: true

module Admin
  module Modules
    module Emails
      class SendActivitiesController < ApplicationController
        dashboard_menu_item :modules

        # A succeed campaign is kept for its metrics — deleting it would orphan the
        # per-recipient Emails::Message ledger.
        DESTROYABLE_STATUSES = %w[pending cancelled].freeze
        # Only pre-send campaigns may have their template/list/schedule changed.
        EDITABLE_STATUSES = %w[pending].freeze

        before_action :require_email_module!
        before_action :load_send_activity, only: %i[show edit update destroy]
        before_action :ensure_editable, only: %i[edit update]

        def index
          @columns = [
            { key: :name,            label: I18n.t("common.labels.name"),      sortable: true, searchable: true },
            { key: :template_name,   label: I18n.t("common.labels.template"),  sortable: false, searchable: false,
              cell: ->(c) { c.email_template&.name || I18n.t("common.labels.em_dash") } },
            { key: :list_name,       label: I18n.t("common.labels.list"),      sortable: false, searchable: false,
              cell: ->(c) {
                names = c.email_lists.map(&:name)
                names.present? ? names.join(", ") : I18n.t("common.labels.em_dash")
              } },
            { key: :status,          label: I18n.t("common.labels.status"),    type: :badge, sortable: true,
              badge: ->(c) { { variant: c.status_variant, label: c.status_label } },
              cell:  ->(c) { c.status_label } },
            { key: :scheduled_at,    label: I18n.t("common.labels.scheduled"), type: :datetime, sortable: true },
            { key: :recurrence_rule, label: I18n.t("common.labels.recurrence"), type: :truncate, sortable: false, searchable: false, truncate: 60 },
            { key: :updated_at,      label: I18n.t("common.labels.updated_at"),   type: :datetime, sortable: true }
          ]
          scope  = ::Emails::SendActivities::SendActivity.for_current_customer.includes(:email_template, :email_lists).order(created_at: :desc)
          result = ModuleEntriesResolver.call(
            scope:   scope, columns: @columns,
            params:  params.permit(:page, :per_page, :sort, :dir, :q).to_h.symbolize_keys
          )
          @rows       = result[:rows]
          @pagination = result[:pagination]
        end

        def show
          @delivery_counts = @send_activity.delivery_counts
        end

        def new
          @send_activity = ::Emails::SendActivities::SendActivity.new(
            customer: current_customer, status: "pending", timezone: "UTC", stats: {}, send_timing: "now"
          )
          load_form_collections
        end

        def create
          @send_activity = ::Emails::SendActivities::SendActivity.new(customer: current_customer)
          result = ::Emails::SendActivities::Build.call(@send_activity, params)
          if result[:success]
            redirect_to "/#{current_customer.id}/admin/modules/emails/send_activities/#{result[:send_activity].id}",
                        notice: t("admin_modules.flash.send_activities.created")
          else
            @send_activity = result[:send_activity]
            load_form_collections
            render :new, status: :unprocessable_entity
          end
        end

        def edit
          @send_activity.send_timing ||= "later"
          load_form_collections
        end

        def update
          result = ::Emails::SendActivities::Build.call(@send_activity, params)
          if result[:success]
            redirect_to "/#{current_customer.id}/admin/modules/emails/send_activities/#{@send_activity.id}",
                        notice: t("admin_modules.flash.send_activities.updated")
          else
            @send_activity = result[:send_activity]
            load_form_collections
            render :edit, status: :unprocessable_entity
          end
        end

        def destroy
          unless DESTROYABLE_STATUSES.include?(@send_activity.status)
            return redirect_to "/#{current_customer.id}/admin/modules/emails/send_activities/#{@send_activity.id}",
                               alert: t("admin_modules.flash.send_activities.delete_status_blocked",
                                        status: @send_activity.status_label)
          end
          if @send_activity.destroy
            redirect_to "/#{current_customer.id}/admin/modules/emails/send_activities", notice: t("admin_modules.flash.send_activities.deleted")
          else
            redirect_to "/#{current_customer.id}/admin/modules/emails/send_activities/#{@send_activity.id}",
                        alert: @send_activity.errors.full_messages.to_sentence.presence ||
                          t("admin_modules.flash.send_activities.delete_status_blocked", status: @send_activity.status_label)
          end
        end

        private

        def require_email_module!
          return if FeatureModules::Module.enabled?(key: "email", customer_id: current_customer.id)

          head :not_found
        end

        def load_send_activity
          @send_activity = ::Emails::SendActivities::SendActivity.for_current_customer
                                                                   .includes(:email_template, :email_lists)
                                                                   .find(params[:id])
        end

        def ensure_editable
          return if EDITABLE_STATUSES.include?(@send_activity.status)

          redirect_to "/#{current_customer.id}/admin/modules/emails/send_activities/#{@send_activity.id}",
                      alert: t("admin_modules.flash.send_activities.edit_status_blocked",
                                status: @send_activity.status_label)
        end

        def load_form_collections
          @templates = ::Emails::Template.for_current_customer.where(status: "active").order(:name)
          @lists     = ::Emails::Audience::List.for_current_customer.order(:name)
        end
      end
    end
  end
end
