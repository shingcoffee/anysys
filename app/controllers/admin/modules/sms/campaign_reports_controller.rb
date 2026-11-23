# frozen_string_literal: true

module Admin
  module Modules
    module Sms
      class CampaignReportsController < BaseController
        def show
          @campaign = scoped_find(::Sms::Campaign, :campaign_id)
          @columns = [column(:name, cell: ->(recipient) { recipient.contact_snapshot["name"] }),
                      column(:phone_e164, sortable: true, searchable: true), status_column(:status, namespace: :recipient_status),
                      column(:message_status, cell: ->(recipient) { recipient.message ? t("sms_campaign_http.message_status.#{recipient.message.status}") : t("common.labels.em_dash") }),
                      column(:skip_reason, cell: ->(recipient) { recipient.skip_reason ? t("sms_campaigns.reasons.#{recipient.skip_reason}") : t("common.labels.em_dash") }),
                      column(:admitted_at, type: :datetime, sortable: true)]
          @filters = read_filters(%i[q status message_status skip_reason page per_page sort dir],
                                  enums: { status: ::Sms::CampaignRecipient::STATUSES, message_status: ::Sms::Message::STATUSES,
                                           skip_reason: ::Sms::CampaignRecipient::SKIP_REASONS, dir: %w[asc desc] })
          unless @filters[:sort].blank? || %w[phone_e164 status admitted_at].include?(@filters[:sort])
            raise ::Sms::RequestAttributes::Invalid.new(:sort, :invalid_filter)
          end
          scope = filtered_recipients
          result = ::Sms::Campaigns::Report.call(customer: current_customer, campaign: @campaign, refresh: false)
          return render_failure(result, template: :show) unless result.success?

          @report = result.value
          if request.format.csv?
            response.headers["Content-Type"] = "text/csv; charset=utf-8"
            response.headers["Content-Disposition"] = %(attachment; filename="sms-campaign-#{@campaign.id}.csv")
            response.headers["Cache-Control"] = "no-store"
            self.response_body = ::Sms::CampaignReportCsv.call(scope: scope, customer: current_customer)
          else
            resolved = ModuleEntriesResolver.call(scope: scope, columns: @columns,
                                                    params: @filters.except(:q), per_page: 25, max_per_page: 100)
            @records, @pagination = resolved.values_at(:rows, :pagination)
            render_surface(:show, data: index_data.merge(campaign: public_record(@campaign), report: @report))
          end
        end

        private

        def filtered_recipients
          scope = tenant_scope(::Sms::CampaignRecipient).where(campaign_id: @campaign.id).includes(:message, :contact).order(:id)
          scope = scope.where(status: @filters[:status]) if @filters[:status].present?
          scope = scope.where(skip_reason: @filters[:skip_reason]) if @filters[:skip_reason].present?
          if @filters[:message_status].present?
            scope = scope.where(message_id: tenant_scope(::Sms::Message).where(status: @filters[:message_status]).select(:id))
          end
          if @filters[:q].present?
            query = "%#{ActiveRecord::Base.sanitize_sql_like(@filters[:q])}%"
            # Snapshot names are historical. Arel quotes the fixed JSON key; no
            # request-supplied JSON path/SQL expression is accepted.
            table = ::Sms::CampaignRecipient.arel_table
            name = Arel::Nodes::NamedFunction.new("json_extract", [table[:contact_snapshot], Arel::Nodes.build_quoted("$.name")])
            scope = scope.where(name.matches(query, "\\").or(table[:phone_e164].matches(query, "\\")))
          end
          scope
        end
      end
    end
  end
end
