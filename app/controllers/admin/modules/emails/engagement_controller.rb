# frozen_string_literal: true

module Admin
  module Modules
    module Emails
      class EngagementController < ApplicationController
        dashboard_menu_item :modules

        def index
          redirect_to admin_modules_emails_health_index_path(current_customer), status: :moved_permanently
        end
      end
    end
  end
end
