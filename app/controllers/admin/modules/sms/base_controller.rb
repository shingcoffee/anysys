# frozen_string_literal: true

module Admin
  module Modules
    module Sms
      class BaseController < ApplicationController
        dashboard_menu_item :modules
        wrap_parameters false

        before_action :require_sms_admin!
        before_action :require_sms_module!
        before_action :check_sms_body!
        before_action :initialize_sms_assigns

        rescue_from ::Sms::RequestAttributes::Invalid, with: :input_error
        rescue_from ActiveRecord::RecordNotFound, with: :sms_not_found

        private

        def require_sms_admin!
          authenticate_user!
          return if performed?
          return if current_user&.admin_or_owner? &&
                    (current_user.platform_owner? || current_user.customer_id == current_customer_id)

          raise CanCan::AccessDenied, t("common.errors.authorization.admin_required")
        end

        def require_sms_module!
          sms_not_found unless current_customer && FeatureModules::Module.enabled?(key: "sms", customer_id: current_customer_id)
        end

        def check_sms_body!
          ::Sms::RequestAttributes.check_body!(request) unless request.get? || request.head?
        end

        def initialize_sms_assigns
          @errors = {}
          @preview = @sync_result = @report = nil
        end

        def tenant_scope(model)
          model.where(customer_id: current_customer_id)
        end

        def scoped_find(model, key = :id)
          id = ::Sms::RequestAttributes.integer(request.path_parameters[key], field: key, minimum: 1)
          tenant_scope(model).find(id)
        rescue ::Sms::RequestAttributes::Invalid
          raise ActiveRecord::RecordNotFound
        end

        def form_attributes(kind, record: nil, extras: [])
          parser = ::Sms::RequestAttributes.new(request: request, kind: kind,
                                                timezone: record&.try(:timezone) || "Asia/Shanghai", extras: extras)
          attributes = parser.call
          @form_values = (record ? ::Sms::FormValues.for(record, kind: kind) : {}).merge(parser.form_values)
          attributes
        end

        def action_attributes(*allowed)
          ::Sms::RequestAttributes.action_inputs(request, allowed: allowed)
        end

        def result_status(result)
          code = result.code.to_s
          return :not_found if %w[not_found inaccessible module_disabled].include?(code)
          return :forbidden if code == "forbidden"
          return :conflict if %w[stale_edit review_changed not_draft cannot_cancel event_key_conflict segment_in_use].include?(code)

          :unprocessable_entity
        end

        def render_failure(result, template:)
          @errors = result.errors
          respond_to do |format|
            format.json { render json: { error: { code: result.code, errors: @errors } }, status: result_status(result) }
            format.html { render template, status: result_status(result) }
          end
        end

        def success_response(data, location:, status: :ok, notice: :saved)
          respond_to do |format|
            format.json { render json: { data: data }, status: status }
            format.html { redirect_to location, status: :see_other, notice: t("sms_campaign_http.flash.#{notice}") }
          end
        end

        def render_surface(template, data:, status: :ok)
          respond_to do |format|
            format.json { render json: { data: data }, status: status }
            format.html { render template, status: status }
          end
        end

        def input_error(error)
          @errors = error.errors
          respond_to do |format|
            format.json { render json: { error: { code: error.code, errors: @errors } }, status: :unprocessable_entity }
            format.any { render plain: @errors.values.flatten.join(" "), status: :unprocessable_entity }
          end
        end

        def sms_not_found(_error = nil)
          @errors = { base: [t("sms_campaign_http.errors.not_found")] }
          respond_to do |format|
            format.json { render json: { error: { code: :not_found, errors: @errors } }, status: :not_found }
            format.any { render plain: @errors[:base].first, status: :not_found }
          end
        end

        def read_filters(allowed, enums: {})
          raw = ::Sms::RequestAttributes.action_inputs(request, allowed: allowed)
          raw.each do |key, value|
            if %i[page per_page].include?(key)
              raw[key] = ::Sms::RequestAttributes.integer(value, field: key, minimum: 1)
            elsif !value.is_a?(String) || value.bytesize > 1024 || !value.valid_encoding?
              raise ::Sms::RequestAttributes::Invalid.new(key, :string_required)
            elsif enums[key] && value.present? && !enums[key].include?(value)
              raise ::Sms::RequestAttributes::Invalid.new(key, :invalid_filter)
            end
          end
          raw[:per_page] = [raw.fetch(:per_page, 25), 100].min
          raw[:page] ||= 1
          raw
        end

        def paginate(scope, columns:, filters: [], accepted: %i[q page per_page sort dir], enums: {})
          @columns = columns
          @filters = read_filters(accepted, enums: enums.merge(dir: %w[asc desc]))
          sortable = @columns.select { |column| column[:sortable] }.map { |column| column[:key].to_s }
          if @filters[:sort].present? && !sortable.include?(@filters[:sort])
            raise ::Sms::RequestAttributes::Invalid.new(:sort, :invalid_filter)
          end
          result = ModuleEntriesResolver.call(scope: scope, columns: columns, params: @filters,
                                              filters: filters, per_page: 25, max_per_page: 100)
          @records, @pagination = result.values_at(:rows, :pagination)
        end

        def index_data
          { records: @records.map { |record| public_record(record) },
            columns: @columns.map { |column| column.slice(:key, :label, :type, :sortable, :searchable) },
            pagination: @pagination, filters: @filters }
        end

        def public_record(record)
          case record
          when ::Sms::Contact
            record.attributes.slice("id", "phone_e164", "name", "country_code", "timezone", "status", "consent_status",
                                    "consent_changed_at", "custom_attributes", "source_kind", "synced_at", "lock_version", "created_at", "updated_at")
          when ::Sms::Campaign
            record.attributes.slice("id", "name", "template_id", "segment_id", "send_timing", "scheduled_at", "timezone",
                                    "quiet_hours_start", "quiet_hours_end", "frequency_window_hours", "send_rate_per_minute", "deadline_hours",
                                    "status", "lock_version", "launched_at", "started_at", "expires_at", "finished_at", "cancelled_at", "failure_code")
          when ::Sms::Audience::Segment
            record.attributes.slice("id", "name", "description", "segment_rules", "lock_version", "created_at", "updated_at")
          when ::Sms::CampaignRecipient
            record.attributes.slice("id", "campaign_id", "contact_id", "phone_e164", "status", "skip_reason", "deferral_reason", "message_id", "delivery_due_at", "admitted_at", "processed_at")
                  .merge("name" => record.contact_snapshot["name"], "message_status" => record.message&.status)
          end
        end

        def column(key, label: nil, **options)
          common = { name: "name", status: "status", description: "description", updated_at: "updated_at", scheduled_at: "scheduled" }
          label ||= common.key?(key) ? "common.labels.#{common[key]}" : "sms_campaign_http.labels.#{key}"
          { key: key, label: t(label), **options }
        end

        def status_column(key, namespace: key)
          column(key, type: :badge, sortable: true,
                 cell: ->(record) { t("sms_campaign_http.#{namespace}.#{record.public_send(key)}") },
                 badge: ->(record) { { label: t("sms_campaign_http.#{namespace}.#{record.public_send(key)}"),
                                      variant: { "granted" => :success, "completed" => :success, "delivered" => :success,
                                                 "scheduled" => :info, "running" => :info, "revoked" => :warning,
                                                 "archived" => :warning, "failed" => :danger }[record.public_send(key)] || :default } })
        end
      end
    end
  end
end
