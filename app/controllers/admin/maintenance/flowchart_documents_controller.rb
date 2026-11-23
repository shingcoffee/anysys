# frozen_string_literal: true

module Admin
  module Maintenance
    class FlowchartDocumentsController < ApplicationController
      dashboard_menu_item :maintenance
      before_action :find_flowchart

      def show
        documenter = FlowchartDocumenter.new(@flowchart)
        markdown = documenter.generate
        slug = @flowchart.name.parameterize.presence || "flowchart-#{@flowchart.id}"
        render json: { markdown: markdown, filename: "#{slug}-docs.md" }
      end

      private

      def find_flowchart
        @flowchart = Flowchart.accessible.find(params[:flowchart_id])
      end
    end
  end
end
