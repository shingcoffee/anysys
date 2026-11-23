# frozen_string_literal: true

module Admin
module Maintenance
  class CustomerProfilesController < ApplicationController
    dashboard_menu_item :maintenance

    def show
      @customer = current_customer
    end

    def edit
      @customer = current_customer
    end

    def update
      @customer = current_customer
      if @customer.update(customer_params)
        redirect_to admin_maintenance_customer_profile_path(current_customer_id),
                    notice: t("maint_core.flash.customer_profiles.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    # Tenant admins manage descriptive profile attributes only. `tier` is a
    # billing-relevant attribute and must stay platform-controlled — a
    # tenant admin promoting their own customer from basic to enterprise
    # would be a privilege/billing escalation.
    def customer_params
      attrs = %i[name alias address contact phone industry]
      attrs << :tier if current_user&.platform_owner?
      params.require(:customer).permit(*attrs)
    end
  end
end
end
