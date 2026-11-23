# frozen_string_literal: true

module Admin
  module Maintenance
    module Flowcharts
      class ImplicitKeysController < ApplicationController
        dashboard_menu_item :maintenance

        CONFIG_PATH = Rails.root.join("config", "flowchart_validation.yml").freeze

        def show
          config = YAML.safe_load_file(CONFIG_PATH)
          render json: { implicit_keys: config["implicit_context_keys"] || [] }
        end
      end
    end
  end
end
