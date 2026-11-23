# frozen_string_literal: true

module Admin
  module Modules
    module Emails
      class TemplatesController < ApplicationController
        dashboard_menu_item :modules

        # Badge tone per lifecycle status: drafts are works-in-progress (warning),
        # active templates are live (success), retired ones fade back (default).
        STATUS_BADGE_VARIANTS = { "active" => :success, "draft" => :warning, "retired" => :default }.freeze

        # Correlated subquery so the list can show per-template usage without
        # eager-loading message rows.
        USAGE_SELECT_SQL = "email_templates.*, " \
                           "(SELECT COUNT(*) FROM email_messages " \
                           "WHERE email_messages.email_template_id = email_templates.id) AS messages_count".freeze

        before_action :require_email_module!, only: %i[create update destroy duplicate status test_send]
        before_action :load_template, only: %i[show edit update destroy status test_send preview duplicate], if: -> { params[:id].present? }

        helper_method :template_status_actions

      def index
        respond_to do |format|
          format.html do
            # One catalog per request: the name column's subtitle decodes the
            # stored {{uuid}} subject tokens to {{Label}} for display.
            token_catalog = ::Emails::TokenCatalog.for_customer(current_customer_id)
            @columns = [
              {
                key: :name,
                label: I18n.t("admin_modules.emails.templates.index.columns.template"),
                sortable: true,
                searchable: true,
                subtitle: ->(t) { ::Emails::TemplateTokenCodec.tokens_to_labels(t.subject, catalog: token_catalog) },
                leading: ->(t) {
                  t.editor_type == "code" ? { icon: :code, tone: :purple } : { icon: :document, tone: :accent }
                }
              },
              {
                key: :subject,
                label: I18n.t("common.labels.subject"),
                searchable: true,
                sortable: false,
                display: false
              },
              {
                key: :status,
                label: I18n.t("common.labels.status"),
                type: :badge,
                sortable: true,
                badge: ->(t) {
                  {
                    variant: STATUS_BADGE_VARIANTS.fetch(t.status, :default),
                    label:   I18n.t("common.status.#{t.status}")
                  }
                },
                cell: ->(t) { I18n.t("common.status.#{t.status}") }
              },
              {
                key: :messages_count,
                label: I18n.t("admin_modules.emails.templates.index.columns.messages"),
                type: :number,
                align: :right,
                sortable: false,
                searchable: false,
                cell: ->(t) { t.messages_count }
              },
              {
                key: :updated_at,
                label: I18n.t("common.labels.updated_at"),
                type: :datetime,
                relative: true,
                sortable: true
              }
            ]
            scope = ::Emails::Template.for_current_customer
                                      .select(Arel.sql(USAGE_SELECT_SQL))
                                      .order(updated_at: :desc)
            if params[:status].present? && ::Emails::Template::STATUSES.include?(params[:status])
              scope = scope.where(status: params[:status])
            end

            @table_filters = [
              {
                key: :status,
                label: I18n.t("admin_modules.emails.templates.index.filters.status"),
                options: ::Emails::Template::STATUSES.map { |s|
                  [I18n.t("common.status.#{s}"), s]
                }
              }
            ]

            result = ModuleEntriesResolver.call(
              scope: scope, columns: @columns,
              params: params.permit(:page, :per_page, :sort, :dir, :q, :status).to_h.symbolize_keys
            )
            @rows       = result[:rows]
            @pagination = result[:pagination]
            @row_actions = lambda do |template|
              [
                {
                  label: I18n.t("common.actions.edit"),
                  path: edit_admin_modules_emails_template_path(current_customer_id, template)
                },
                {
                  label: I18n.t("admin_modules.emails.templates.actions.preview"),
                  path: preview_admin_modules_emails_template_path(current_customer_id, template)
                }
              ]
            end
          end
          format.json do
            templates = ::Emails::Template.for_current_customer.where(status: "active").order(:name).pluck(:id, :name)
            render json: templates.map { |id, name| { id: id, name: name } }
          end
        end
      end

      def show
        @version_count = @template.template_versions.count
        @preview = ::Emails::AuthorPreview.call(@template, mode: :tokens)
      end

      def new
        @template = ::Emails::Template.new(customer: current_customer, status: "active", editor_type: "rich_text")
      end

      def create
        @template = ::Emails::Template.new(template_params.merge(customer: current_customer))
        if @template.save
          redirect_to "/#{current_customer.id}/admin/modules/emails/templates", notice: t("admin_modules.flash.templates.created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        apply_version_preview! if params[:version].present?
      end

      def update
        if @template.update(template_params)
          redirect_to "/#{current_customer.id}/admin/modules/emails/templates", notice: t("admin_modules.flash.templates.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def status
        if @template.update_status!(params.require(:status))
          redirect_to admin_modules_emails_templates_path(current_customer_id),
                      notice: t("admin_modules.flash.templates.updated")
        else
          redirect_to admin_modules_emails_templates_path(current_customer_id),
                      alert: @template.errors[:status].to_sentence.presence ||
                             t("admin_modules.emails.templates.status.in_use")
        end
      end

      def template_status_actions(template = @template)
        status_actions_for(template).map do |action|
          {
            label: action[:label],
            path: action[:path],
            variant: :secondary,
            data: { turbo_method: action[:method] }
          }
        end
      end

      # Clones a template as a fresh draft so authors can iterate on a copy
      # without touching a template that live send activities may reference.
      # The rich-text body is assigned explicitly — #dup only copies columns,
      # not the Action Text association.
      def duplicate
        copy = @template.dup
        # #dup copies current_version_id. Autocommit then no-ops (payload hash
        # matches the source head), so both rows point at the same version.
        # SQLite treats that FK as RESTRICT: deleting the source destroys its
        # versions and 500s while the copy still references them.
        copy.current_version_id = nil
        copy.name   = I18n.t("admin_modules.emails.templates.actions.duplicate_name", name: @template.name).truncate(255)
        copy.status = "draft"
        if @template.editor_type == "rich_text" && @template.body.present?
          copy.body = @template.body.to_trix_html.to_s
        end

        if copy.save
          redirect_to edit_admin_modules_emails_template_path(current_customer_id, copy),
                      notice: t("admin_modules.flash.templates.duplicated")
        else
          redirect_to admin_modules_emails_templates_path(current_customer_id),
                      alert: copy.errors.full_messages.to_sentence
        end
      end

      def destroy
        if @template.in_use_by_non_terminal_send_activity?
          return redirect_to "/#{current_customer.id}/admin/modules/emails/templates",
                             alert: t("admin_modules.flash.templates.delete_restricted")
        end

        @template.destroy
        redirect_to "/#{current_customer.id}/admin/modules/emails/templates", notice: t("admin_modules.flash.templates.deleted")
      rescue ActiveRecord::DeleteRestrictionError
        redirect_to "/#{current_customer.id}/admin/modules/emails/templates",
                    alert: t("admin_modules.flash.templates.delete_restricted")
      end

      def test_send
        if params[:email_template].present?
          @template ||= ::Emails::Template.new(customer: current_customer)
          @template.assign_attributes(template_params)
        end

        @template ||= ::Emails::Template.new(customer: current_customer, editor_type: "code", body_html: "")

        @template.sync_body_html!

        recipients = (params[:to].presence || current_user.email).to_s
                       .split(",").map(&:strip).reject(&:empty?)

        invalid = recipients.reject { |email| email.match?(URI::MailTo::EMAIL_REGEXP) }
        if invalid.any?
          respond_to do |format|
            format.html do
              redirect_to("/#{current_customer.id}/admin/modules/emails/templates",
                          alert: t("admin_modules.flash.templates.invalid_email", email: invalid.first))
            end
            format.json do
              render json: { success: false, error: t("admin_modules.flash.templates.invalid_email", email: invalid.first) }, status: :unprocessable_entity
            end
          end
          return
        end

        vars = ::Emails::VariableContext.for(user: current_user)

        outcomes = recipients.map do |to|
          rendered = ::Emails::TemplateRenderer.render(template: @template, vars: vars)

          if rendered[:subject].to_s.strip.blank? || rendered[:body_html].to_s.strip.blank?
            error = t("admin_modules.flash.templates.blank_content")
            respond_to do |format|
              format.html do
                redirect_to("/#{current_customer.id}/admin/modules/emails/templates",
                            alert: error)
              end
              format.json do
                render json: { success: false, error: error }, status: :unprocessable_entity
              end
            end
            return
          end

          ::Emails::Gateway.send_raw(
            customer:            current_customer,
            to:                  to,
            subject:             rendered[:subject],
            body_html:           rendered[:body_html],
            body_text:           rendered[:body_text],
            attachment_blob_ids: ::Emails::CompileTemplate.blob_ids_for(@template)
          )
        end

        if outcomes.any? && outcomes.all? { |message| message.status == "suppressed" }
          alert = t("admin_modules.flash.templates.suppressed")
          respond_to do |format|
            format.html do
              redirect_back(
                fallback_location: "/#{current_customer.id}/admin/modules/emails/templates",
                alert: alert
              )
            end
            format.json do
              render json: { success: false, error: alert }, status: :unprocessable_content
            end
          end
          return
        end

        notice = if recipients.size == 1
                   t("admin_modules.flash.templates.test_sent", email: recipients.first)
                 else
                   t("admin_modules.flash.templates.test_sent_multi", count: recipients.size)
                 end

        respond_to do |format|
          format.html do
            redirect_back(
              fallback_location: "/#{current_customer.id}/admin/modules/emails/templates",
              notice: notice
            )
          end
          format.json do
            render json: { success: true, message: notice }
          end
        end
      rescue ::Email::Errors::UnsupportedMessage => error
        respond_to do |format|
          format.html do
            redirect_back(fallback_location: "/#{current_customer.id}/admin/modules/emails/templates", alert: error.message)
          end
          format.json do
            render json: { success: false, error: error.message, code: error.code }, status: :unprocessable_entity
          end
        end
      rescue ::Email::Errors::DailyCapExceeded
        respond_to do |format|
          format.html do
            redirect_back(
              fallback_location: "/#{current_customer.id}/admin/modules/emails/templates",
              alert: t("admin_modules.flash.templates.daily_cap_exceeded")
            )
          end
          format.json do
            render json: { success: false, error: t("admin_modules.flash.templates.daily_cap_exceeded") },
                   status: :too_many_requests
          end
        end
      rescue ::Email::Errors::CredentialsMissing
        respond_to do |format|
          format.html do
            redirect_back(
              fallback_location: "/#{current_customer.id}/admin/modules/emails/templates",
              alert: t("admin_modules.flash.templates.credentials_missing")
            )
          end
          format.json do
            render json: { success: false, error: t("admin_modules.flash.templates.credentials_missing") },
                   status: :service_unavailable
          end
        end
      rescue ActiveRecord::RecordInvalid
        respond_to do |format|
          format.html do
            redirect_back(
              fallback_location: "/#{current_customer.id}/admin/modules/emails/templates",
              alert: t("admin_modules.flash.templates.blank_content")
            )
          end
          format.json do
            render json: { success: false, error: t("admin_modules.flash.templates.blank_content") },
                   status: :unprocessable_entity
          end
        end
      end

      # GET  — dedicated author preview page ({{Label}} tokens, no sample fill).
      # POST — editor live preview JSON / full-page sample fill.
      def preview
        if request.get?
          @preview = ::Emails::AuthorPreview.call(@template, mode: :tokens)
          return
        end

        if params[:email_template].present?
          @template ||= ::Emails::Template.new(customer: current_customer)
          @template.assign_attributes(template_params)
        end

        @template ||= ::Emails::Template.new(customer: current_customer, editor_type: "code", body_html: "")

        vars = preview_vars
        return if performed?

        # Same ActionText → body_html sync as save, so unsaved preview matches
        # what would be persisted.
        @template.sync_body_html!

        rendered = ::Emails::AuthorPreview.call(
          @template, mode: :sample, vars: vars, user: current_user
        )

        # Always JSON — never serve authored HTML as the response document.
        # A navigated POST ?preview_mode=full_page would otherwise XSS the
        # admin origin. The editor new-tab path puts body_srcdoc into a
        # sandboxed iframe.
        render json: {
          subject:     rendered[:subject],
          body_html:   rendered[:body_html],
          body_text:   rendered[:body_text],
          body_srcdoc: rendered[:body_srcdoc]
        }
      rescue JSON::ParserError
        render json: { error: t("admin_modules.emails.templates.form.preview.invalid_json") }, status: :unprocessable_entity
      end

      private

      def status_actions_for(template)
        ::Emails::Template::STATUSES.filter_map do |new_status|
          next if new_status == template.status

          {
            label: I18n.t("admin_modules.emails.templates.status.actions.set_#{new_status}"),
            path: status_admin_modules_emails_template_path(current_customer_id, template, status: new_status),
            method: :patch
          }
        end
      end

      def require_email_module!
        return if FeatureModules::Module.enabled?(key: "email", customer_id: current_customer.id)

        head :not_found
      end

      def load_template
        @template = ::Emails::Template.for_current_customer.find(params[:id])
      end

      # Preview fill vars must be a JSON object. Missing/blank (except a JSON
      # string, which may still parse) falls back to the signed-in user's
      # sample context. Arrays and other JSON types 422 instead of 500ing
      # inside AuthorPreview.
      def preview_vars
        raw = params[:vars]
        return ::Emails::VariableContext.for(user: current_user) if omit_preview_vars?(raw)

        parsed = case raw
                 when String then JSON.parse(raw)
                 when ActionController::Parameters then raw.to_unsafe_h
                 else raw
                 end
        return parsed if parsed.is_a?(Hash)

        render json: { error: t("admin_modules.emails.templates.form.preview.vars_must_be_object") },
               status: :unprocessable_entity
        nil
      end

      def omit_preview_vars?(raw)
        raw.nil? || (!raw.is_a?(String) && raw.blank?)
      end

      # Applies a historical version's payload onto @template in memory (no
      # save) so the edit form previews that version's content. Silently
      # no-ops for an unknown/foreign version id rather than 404ing what is
      # otherwise a normal edit page load.
      def apply_version_preview!
        version = @template.template_versions.find_by(id: params[:version])
        return unless version

        payload = version.payload_json
        @template.assign_attributes(
          subject:     payload["subject"],
          body_html:   payload["body_html"],
          body_text:   payload["body_text"],
          editor_type: payload["editor_type"]
        )
        @template.body = payload["body_raw"] if @template.editor_type == "rich_text"
      end

      def template_params
        attributes = [:name, :subject, :body, :body_html, :body_text, :editor_type]
        attributes << :status if action_name == "create"
        params.require(:email_template).permit(*attributes)
      end
      end
    end
  end
end
