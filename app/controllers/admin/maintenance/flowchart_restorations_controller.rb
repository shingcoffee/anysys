# frozen_string_literal: true

module Admin
  module Maintenance
    class FlowchartRestorationsController < BaseRestorationsController
      restorable finder: -> { deleted_definition_scope(Flowchart).find(params[:flowchart_id]) },
                 redirect: -> { admin_maintenance_flowcharts_url(current_customer_id) },
                 flash_key: "maint_core.flash.flowchart_restorations.restored"
    end
  end
end
