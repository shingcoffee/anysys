# frozen_string_literal: true

module Admin
  module Modules
    module Emails
      class ReportsController < ApplicationController
        dashboard_menu_item :modules

        def index
          redirect_to admin_modules_emails_dashboard_path(current_customer), status: :moved_permanently
        end
      end
    end
  end
end
