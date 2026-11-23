# frozen_string_literal: true

module Admin
  module Modules
    module Emails
    class ListsController < ApplicationController
      dashboard_menu_item :modules

      before_action :require_email_module!, only: %i[create update destroy]
      before_action :load_list, only: %i[show edit update destroy]

      TYPE_BADGE_VARIANTS = { "static" => :primary, "dynamic" => :purple }.freeze

      def index
        respond_to do |format|
          format.html do
            @columns = [
              {
                key: :name,
                label: I18n.t("admin_modules.emails.lists.index.columns.list"),
                sortable: true,
                searchable: true,
                subtitle: ->(l) { l.description.to_s.presence },
                leading: ->(l) {
                  l.static? ? { icon: :mail, tone: :accent } : { icon: :document, tone: :purple }
                }
              },
              {
                key: :description,
                label: I18n.t("common.labels.description"),
                searchable: true,
                sortable: false,
                display: false
              },
              {
                key: :list_type,
                label: I18n.t("common.labels.type"),
                type: :badge,
                sortable: true,
                badge: ->(l) {
                  {
                    variant: TYPE_BADGE_VARIANTS.fetch(l.list_type, :default),
                    label:   I18n.t("admin_modules.emails.lists.form.types.#{l.list_type}")
                  }
                },
                cell: ->(l) { I18n.t("admin_modules.emails.lists.form.types.#{l.list_type}") }
              },
              {
                key: :audience,
                label: I18n.t("admin_modules.emails.lists.index.columns.audience"),
                type: :number,
                align: :right,
                sortable: false,
                searchable: false,
                cell: ->(l) { l.audience_count }
              },
              {
                key: :updated_at,
                label: I18n.t("common.labels.updated_at"),
                type: :datetime,
                relative: true,
                sortable: true
              }
            ]

            scope = ::Emails::Audience::List.for_current_customer.order(updated_at: :desc)
            if params[:list_type].present? && ::Emails::Audience::List::LIST_TYPES.include?(params[:list_type])
              scope = scope.where(list_type: params[:list_type])
            end

            @table_filters = [
              {
                key: :list_type,
                label: I18n.t("admin_modules.emails.lists.index.filters.type"),
                options: ::Emails::Audience::List::LIST_TYPES.map { |lt|
                  [I18n.t("admin_modules.emails.lists.form.types.#{lt}"), lt]
                }
              }
            ]

            result = ModuleEntriesResolver.call(
              scope:   scope,
              columns: @columns,
              params:  params.permit(:page, :per_page, :sort, :dir, :q, :list_type).to_h.symbolize_keys
            )
            @rows       = result[:rows]
            @pagination = result[:pagination]
            @row_actions = lambda do |list|
              [
                {
                  label: I18n.t("common.actions.edit"),
                  path: edit_admin_modules_emails_list_path(current_customer_id, list)
                }
              ]
            end
          end
          format.json do
            lists = ::Emails::Audience::List.for_current_customer.order(:name).pluck(:id, :name)
            render json: lists.map { |id, name| { id: id, name: name } }
          end
        end
      end

      def preview
        rules = parse_preview_rules
        return render_preview_malformed if @segment_rules_error

        scope = ::Emails::Audience::SegmentQuery.call(customer: current_customer, rules: rules)
                 .order(:email)

        @columns = [
          { key: :email, label: I18n.t("common.labels.email"), sortable: false, searchable: false },
          { key: :first_name, label: I18n.t("common.labels.first_name"), sortable: false, searchable: false },
          { key: :last_name, label: I18n.t("common.labels.last_name"), sortable: false, searchable: false }
        ]

        result = ModuleEntriesResolver.call(
          scope:   scope,
          columns: @columns,
          params:  params.permit(:page, :per_page, :sort, :dir).to_h.symbolize_keys
        )
        @rows               = result[:rows]
        @pagination         = result[:pagination]
        @match_count        = result[:pagination][:total]
        @preview_rules_json = rules.to_json

        render partial: "preview", layout: false
      end

      def show
        @audience_count = @list.audience_count
        @member_emails = if @list.static?
          @list.users.order(:email).limit(ModuleEntriesResolver::MAX_PER_PAGE).pluck(:email)
        else
          []
        end
      end

      def new
        @list = ::Emails::Audience::List.new(customer: current_customer,
                                             list_type: "dynamic", segment_rules: {})
      end

      def create
        @list = ::Emails::Audience::List.new(list_params.merge(customer: current_customer))
        if @segment_rules_error
          @list.errors.add(:base, t("admin_modules.errors.lists.segment_malformed"))
          return render :new, status: :unprocessable_entity
        end
        if ::Emails::Audience::SaveList.call(list: @list)
          sync_static_memberships!(@list)
          redirect_to lists_path, notice: t("admin_modules.flash.lists.created"),
                      alert: unknown_static_emails_alert
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        attrs = list_params
        if @segment_rules_error
          @list.errors.add(:base, t("admin_modules.errors.lists.segment_malformed"))
          return render :edit, status: :unprocessable_entity
        end
        if ::Emails::Audience::SaveList.call(list: @list, attributes: attrs)
          sync_static_memberships!(@list)
          redirect_to "#{lists_path}/#{@list.id}", notice: t("admin_modules.flash.lists.updated"),
                      alert: unknown_static_emails_alert
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @list.destroy
        redirect_to lists_path, notice: t("admin_modules.flash.lists.deleted")
      rescue ActiveRecord::DeleteRestrictionError
        redirect_to lists_path, alert: t("admin_modules.flash.lists.delete_restricted")
      end

      private

      def lists_path
        "/#{current_customer.id}/admin/modules/emails/lists"
      end

      def require_email_module!
        return if FeatureModules::Module.enabled?(key: "email", customer_id: current_customer.id)

        head :not_found
      end

      def load_list
        @list = ::Emails::Audience::List.for_current_customer.find(params[:id])
      end

      def parse_preview_rules
        contract = ::Emails::Audience::Contracts::SegmentRules.from_json(params[:segment_rules_json])
        @segment_rules_error = !contract.errors.empty?
        @segment_rules_error ? {} : contract.rules
      end

      def render_preview_malformed
        @preview_error = t("admin_modules.emails.lists.preview.malformed")
        render partial: "preview", layout: false, status: :unprocessable_entity
      end

      # Membership sync applies only to static lists, and only when the emails
      # textarea was submitted (metadata-only updates must not wipe members).
      def sync_static_memberships!(list)
        return unless list.static?
        return unless params.key?(:email_list_static_emails)

        emails = params[:email_list_static_emails].to_s.split(/[\r\n,;]+/).map(&:strip).reject(&:blank?).map(&:downcase)

        users = ::Authentication::User.for_current_customer.where("LOWER(email) IN (?)", emails)
        unknown = emails - users.pluck(:email).map(&:downcase)
        @unknown_static_emails = unknown

        list.list_memberships.where.not(user_id: users.select(:id)).destroy_all
        users.each do |user|
          list.list_memberships.find_or_create_by!(user: user)
        end
      end

      def unknown_static_emails_alert
        return if @unknown_static_emails.blank?

        t("admin_modules.flash.lists.unknown_emails", emails: @unknown_static_emails.join(", "))
      end

      def list_params
        submitted = params.require(:email_list)
        permitted = submitted.permit(:name, :description, :list_type)

        if submitted.key?(:segment_rules_json)
          contract = ::Emails::Audience::Contracts::SegmentRules.from_json(submitted[:segment_rules_json])
          if contract.errors.empty?
            permitted[:segment_rules] = contract.rules
          else
            @segment_rules_error = true
          end
        end

        list_type = permitted.key?(:list_type) ? permitted[:list_type] : (@list&.list_type || "dynamic")
        if list_type == "static" && (permitted.key?(:list_type) || submitted.key?(:segment_rules_json))
          permitted[:segment_rules] = {}
        end
        permitted[:list_type] = list_type if @list.nil?

        permitted.permit!
        permitted.to_h
      end
    end
    end
  end
end
