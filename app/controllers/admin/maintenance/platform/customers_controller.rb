# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  class CustomersController < ApplicationController
    dashboard_menu_item :maintenance
    include SoftDeletableController

    soft_deletable Customer

    # Reject a forged outer CID before loading or updating an HTML profile.
    # JSON keeps its existing interface.
    before_action :require_platform_customer_path!, only: %i[index show edit update],
                  if: -> { action_name == "index" || html_profile_request? }
    before_action :set_customer, only: %i[show edit update destroy]

    def index
      prepare_customers_index

      respond_to do |format|
        format.html
        format.json { render json: @customers }
      end
    end

    def trash
      @columns = [
        { key: :name,         label: I18n.t("common.labels.name"),     sortable: true, searchable: true },
        { key: :alias,        label: I18n.t("common.labels.alias"),    sortable: true, searchable: true },
        { key: :users_count,  label: I18n.t("common.labels.users"),    type: :number, sortable: false, searchable: false,
          cell: ->(c) { c.users.size } },
        { key: :modules_count, label: I18n.t("common.labels.modules"), type: :number, sortable: false, searchable: false,
          cell: ->(c) { c.feature_modules.size } },
        { key: :created_at,   label: I18n.t("common.labels.created_at"),  type: :datetime, sortable: true }
      ]
      scope  = Customer.only_deleted.includes(:users, :feature_modules).order(updated_at: :desc)
      result = ModuleEntriesResolver.call(
        scope: scope, columns: @columns,
        params: params.permit(:q, :sort, :dir, :page, :per_page).to_h.symbolize_keys
      )
      @customers  = result[:rows]
      @rows       = result[:rows]
      @pagination = result[:pagination]
    end

    def empty_trash
      result = ::Customers::Purge.call(customers: Customer.only_deleted)
      respond_to do |format|
        if result.success?
          format.html do
            redirect_to trash_admin_maintenance_platform_customers_path(current_customer_id),
                        notice: t("maint_platform.flash.customers.permanently_deleted", count: result.deleted_count)
          end
          format.json { render json: { success: true, count: result.deleted_count } }
        else
          message = if result.error_code == :platform_customer
            t("maint_platform.flash.customers.platform_protected")
          else
            t("routes_audit.customer_purge_failed")
          end
          format.html { redirect_to trash_admin_maintenance_platform_customers_path(current_customer_id), alert: message }
          format.json { render json: { success: false, error: message }, status: :unprocessable_entity }
        end
      end
    end

    def show
      respond_to do |format|
        format.html
        format.json { render json: @customer }
      end
    end

    def new
      @customer = Customer.new
    end

    def create
      @customer = Customer.new(customer_params)

      if @customer.save
        respond_to do |format|
          format.html { redirect_to admin_maintenance_platform_customers_path(current_customer_id), notice: t("maint_platform.flash.customers.created") }
          format.json { render json: @customer, status: :created }
        end
      else
        respond_to do |format|
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: { errors: @customer.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    def update
      if @customer.update(customer_params)
        respond_to do |format|
          format.html { redirect_to admin_maintenance_platform_customer_path(current_customer_id, @customer), notice: t("maint_platform.flash.customers.updated") }
          format.json { render json: @customer }
        end
      else
        respond_to do |format|
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: { errors: @customer.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      if @customer.soft_delete
        respond_to do |format|
          format.html { redirect_to admin_maintenance_platform_customers_path(current_customer_id), notice: t("maint_platform.flash.customers.deleted") }
          format.json { head :no_content }
        end
      else
        message = @customer.errors.full_messages.to_sentence.presence || t("routes_audit.customer_deletion_failed")
        respond_to do |format|
          format.html { redirect_to admin_maintenance_platform_customers_path(current_customer_id), alert: message }
          format.json { render json: { errors: @customer.errors.full_messages.presence || [message] }, status: :unprocessable_entity }
        end
      end
    end

    private

    def html_profile_request?
      # Wildcard Accept negotiates HTML in respond_to and implicit rendering.
      request.format.html? || request.format == Mime::ALL
    end

    def set_customer
      scope = action_name == "show" ? Customer.unscoped : Customer
      @customer = scope.find(request.path_parameters[:id])
    end

    def customer_params
      # `:role` is intentionally NOT permitted: tenant role assignment
      # flows through the RBAC users_roles table, not the Customer record,
      # and accepting it here would let a platform admin promote a tenant
      # to a sensitive enum without any role check on the user side.
      params.require(:customer).permit(
        :name,
        :alias,
        :address,
        :contact,
        :phone,
        :tier,
        :industry,
        :locale,
        :domain
      )
    end

    def require_platform_customer_path!
      head :not_found unless request.path_parameters[:customer_id] == Authentication::User::PLATFORM_CUSTOMER_ID.to_s
    end

    def prepare_customers_index
      @columns = customer_index_columns
      @table_context = params.permit(:q, :sort, :dir, :page).to_h.select do |_, value|
        value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
      end
      scope = Customer.includes(:users, :feature_modules).order(:name)
      result = ModuleEntriesResolver.call(
        scope: scope, columns: @columns,
        params: @table_context.slice("q", "sort", "dir", "page").symbolize_keys
      )
      @customers  = result[:rows]
      @rows       = result[:rows]
      @pagination = result[:pagination]
    end

    def customer_index_columns
      [
        {
          key: :name, label: I18n.t("common.labels.customer"), sortable: true, searchable: true,
          width: "min-w-56",
          subtitle: ->(customer) { customer.alias.presence },
          leading: ->(_customer) { { icon: :building, tone: :accent } }
        },
        {
          key: :id, label: I18n.t("chrome.customer_form.customer_id"), sortable: true, searchable: true,
          mono: true, nowrap: true, width: "w-36",
          sql: "CAST(customers.id AS TEXT)"
        },
        {
          key: :domain, label: I18n.t("chrome.customer_form.domain"), sortable: true, searchable: true,
          mono: true, break: true, width: "min-w-48",
          cell: ->(customer) { customer.domain.presence || I18n.t("common.labels.em_dash") }
        },
        {
          key: :users_count, label: I18n.t("common.labels.users"), type: :number, align: :right,
          sortable: false, searchable: false, width: "w-24",
          cell: ->(customer) { customer.users.size }
        },
        {
          key: :modules_count, label: I18n.t("common.labels.modules"), type: :number, align: :right,
          sortable: false, searchable: false, width: "w-28",
          cell: ->(customer) { customer.feature_modules.size }
        },
        {
          key: :created_at, label: I18n.t("common.labels.created_at"), type: :datetime, relative: true,
          sortable: true, searchable: false, nowrap: true
        },
        {
          key: :alias, label: I18n.t("chrome.customer_form.alias"), sortable: false, searchable: true, display: false
        }
      ]
    end
  end
end
end
end
