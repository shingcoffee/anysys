# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  class CustomerContextsController < ApplicationController
    dashboard_menu_item :maintenance
    before_action :set_customer, only: [:update]

    def search
      query = params[:q].to_s.strip
      customers = Customer.order(:name)
      customers = customers.where("lower(name) LIKE ?", "%#{query.downcase}%") if query.present?
      customers = customers.limit(20)

      render json: customers.map { |c| { id: c.id, name: c.name } }
    end

    def update
      # Platform context is URL-derived on every request. Hand the platform
      # owner over to the target tenant's dashboard; subsequent requests
      # rebuild the context from the path via TenantContext.
      redirect_to "/#{@customer.id}/admin/dashboard", notice: t("maint_platform.flash.customer_contexts.now_acting_as", name: @customer.name)
    end

    def destroy
      clear_platform_owner_context
      redirect_to "/#{current_user.customer_id}/admin/dashboard", notice: t("maint_platform.flash.customer_contexts.returned_to_platform")
    end

    private

    def set_customer
      # The path customer_id is always the platform tenant. The customer to
      # act as arrives in the body (customer_id) or as target_customer_id.
      target_id = request.request_parameters["customer_id"].presence ||
                  request.request_parameters["target_customer_id"].presence ||
                  request.query_parameters["target_customer_id"].presence
      @customer = Customer.find_by(id: target_id)
      render_not_found unless @customer
    end

    def render_not_found
      respond_to do |format|
        format.html { redirect_to root_path, alert: t("maint_platform.flash.customer_contexts.customer_not_found") }
        format.json { render json: { error: "not_found" }, status: :not_found }
      end
    end
  end
end
end
end
