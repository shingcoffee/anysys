# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      class CustomerRestorationsController < BaseRestorationsController
        restorable finder: -> { Customer.only_deleted.find(params[:id]) },
                   redirect: -> { admin_maintenance_platform_customers_path(current_customer_id) },
                   flash_key: "maint_platform.flash.customers.restored"
      end
    end
  end
end
