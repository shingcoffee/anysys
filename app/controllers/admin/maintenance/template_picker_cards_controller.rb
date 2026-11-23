# frozen_string_literal: true

module Admin
  module Maintenance
    # Renders the template card grid on demand so the entity form and the page
    # builder can lazy-load it the first time their picker modal is opened,
    # instead of rendering 100+ cards inline at page load.
    class TemplatePickerCardsController < ApplicationController
      dashboard_menu_item :maintenance

      def show
        templates =
          if params[:scope] == "all"
            PageLayoutTemplates.all
          else
            PageLayoutTemplates.for_industry(current_customer&.industry)
          end

        render(
          partial: "shared/template_picker_grid",
          layout: false,
          locals: {
            templates: templates,
            selected_key: params[:selected].presence,
            controller_name: "template-selector"
          }
        )
      end
    end
  end
end
