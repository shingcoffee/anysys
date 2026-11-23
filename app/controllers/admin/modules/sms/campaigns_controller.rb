# frozen_string_literal: true

module Admin
  module Modules
    module Sms
      class CampaignsController < BaseController
        before_action :load_campaign, only: %i[show edit update destroy]

        def index
          paginate(tenant_scope(::Sms::Campaign).order(created_at: :desc),
                   columns: [column(:name, sortable: true, searchable: true), status_column(:status, namespace: :campaign_status),
                             column(:send_timing, cell: ->(campaign) { t("sms_campaign_http.send_timing.#{campaign.send_timing}") }),
                             column(:scheduled_at, type: :datetime, sortable: true),
                             column(:matched_count, type: :number, cell: ->(campaign) { campaign.started_at ? campaign.stats["matched_count"] : t("sms_campaign_http.labels.not_started") }),
                             column(:updated_at, type: :datetime, sortable: true)],
                   accepted: %i[q status page per_page sort dir], enums: { status: %w[draft scheduled running completed cancelled failed] },
                   filters: [{ key: :status, column: :status }])
          render_surface(:index, data: index_data)
        end

        def new
          @campaign = new_campaign
          prepare_form
          render_form(:new)
        end

        def edit
          return reject_non_draft unless @campaign.status == "draft"

          prepare_form
          render_form(:edit)
        end

        def create
          @campaign = new_campaign
          save_campaign(:new)
        end

        def update
          return reject_non_draft unless @campaign.status == "draft"

          save_campaign(:edit)
        end

        def show
          prepare_show
          render_surface(:show, data: show_data)
        end

        def preview
          @campaign = request.path_parameters[:id] ? scoped_find(::Sms::Campaign) : new_campaign
          return reject_non_draft unless @campaign.status == "draft"

          attributes = form_attributes(:campaign, record: @campaign, extras: [:preview_contact_id])
          @preview_contact_id = selected_contact_id
          prepare_form
          result = ::Sms::Campaigns::Preview.call(customer: current_customer, actor: current_user, campaign: @campaign,
                                                 attributes: attributes, contact_id: @preview_contact_id)
          if result.success?
            @preview = result.value
            render_form(@campaign.persisted? ? :edit : :new)
          else
            render_failure(result, template: @campaign.persisted? ? :edit : :new)
          end
        end

        def destroy
          action_attributes
          result = ::Sms::Campaigns::DeleteDraft.call(customer: current_customer, actor: current_user, campaign: @campaign)
          if result.success?
            success_response({ id: result.value.id }, location: admin_modules_sms_campaigns_path(current_customer_id), notice: :deleted)
          else
            @errors = result.errors
            @campaign.reload
            prepare_show
            render_failure(result, template: :show)
          end
        end

        private

        def load_campaign
          @campaign = scoped_find(::Sms::Campaign)
        end

        def new_campaign
          ::Sms::Campaign.new(customer: current_customer, created_by_id: current_user.id)
        end

        def selected_contact_id
          value = request.query_parameters.merge(request.request_parameters)["preview_contact_id"]
          id = ::Sms::RequestAttributes.integer(value, field: :preview_contact_id, optional: true, minimum: 1)
          tenant_scope(::Sms::Contact).find(id) if id
          id
        end

        def prepare_collections
          @templates = ::Sms::Template.active.where(purpose: "marketing").order(:key).map do |template|
            { id: template.id, key: template.key, label: template.description.presence || template.key,
              required_vars: template.required_vars, body_template: template.body_template }
          end
          @segments = tenant_scope(::Sms::Audience::Segment).order(:name, :id).pluck(:id, :name).map { |id, name| { id: id, name: name } }
          contacts = tenant_scope(::Sms::Contact).order(:id).limit(20).pluck(:id, :name, :phone_e164)
          if @preview_contact_id && contacts.none? { |row| row.first == @preview_contact_id }
            selected = tenant_scope(::Sms::Contact).find(@preview_contact_id)
            contacts = contacts.first(19) + [[selected.id, selected.name, selected.phone_e164]]
          end
          @contacts = contacts.map { |id, name, phone| { id: id, name: name, phone_e164: phone } }
          @errors ||= {}
        end

        def prepare_form
          prepare_collections
          @form_values ||= ::Sms::FormValues.for(@campaign, kind: :campaign)
          @preview ||= nil
        end

        def prepare_show
          prepare_collections
          if @campaign.status == "draft"
            result = ::Sms::Campaigns::Preview.call(customer: current_customer, actor: current_user, campaign: @campaign)
            @preview = result.value if result.success?
            @errors = @errors.merge(result.errors) unless result.success?
          else
            result = ::Sms::Campaigns::Report.call(customer: current_customer, campaign: @campaign, refresh: false)
            @report = result.value if result.success?
            @errors = @errors.merge(result.errors) unless result.success?
          end
        end

        def render_form(template)
          render_surface(template, data: { campaign: public_record(@campaign), templates: @templates, segments: @segments, contacts: @contacts,
                                          form_values: @form_values, preview: @preview, errors: @errors })
        end

        def show_data
          { campaign: public_record(@campaign), templates: @templates, segments: @segments, contacts: @contacts,
            preview: @preview, report: @report, errors: @errors }
        end

        def save_campaign(template)
          # The shared native form submits its sample selector on either button.
          # It is scoped read-only form metadata, never a persisted draft field.
          attributes = form_attributes(:campaign, record: @campaign, extras: [:preview_contact_id])
          @preview_contact_id = selected_contact_id
          result = ::Sms::Campaigns::Save.call(customer: current_customer, actor: current_user,
                                              campaign: @campaign.persisted? ? @campaign : nil, attributes: attributes)
          if result.success?
            @campaign = result.value
            success_response(public_record(@campaign), location: admin_modules_sms_campaign_path(current_customer_id, @campaign), status: template == :new ? :created : :ok)
          else
            prepare_form
            render_failure(result, template: template)
          end
        end

        def reject_non_draft
          error = ::Sms::RequestAttributes::Invalid.new(:base, :not_draft, code: :not_draft)
          @errors = error.errors
          prepare_show
          render_failure(error, template: "admin/modules/sms/campaigns/show")
        end

        def input_error(error)
          return super if action_name == "index"

          @campaign ||= request.path_parameters[:id] ? scoped_find(::Sms::Campaign) : new_campaign
          @errors = error.errors
          @form_values = ::Sms::FormValues.for(@campaign, kind: :campaign).merge(error.form_values)
          @preview = nil
          if %w[launch cancel destroy].include?(action_name) || is_a?(CampaignLaunchesController) || is_a?(CampaignCancellationsController)
            prepare_show
            render_failure(error, template: "admin/modules/sms/campaigns/show")
          else
            prepare_form
            render_failure(error, template: @campaign.persisted? ? :edit : :new)
          end
        end
      end
    end
  end
end
