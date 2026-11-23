# frozen_string_literal: true

module Admin
  module Maintenance
    class PagePreviewsController < ApplicationController
      include SharedResourceMode
      dashboard_menu_item :maintenance
      before_action :find_page

      def show
        render_preview
      end

      def create
        render_preview
      end

      private

      def render_preview
        respond_to do |format|
          format.html do
            @form_action      = resolve_form_action_from_params || "#"
            @original_page_id = @page.id
            # `embed=1` drops the preview chrome so the page can be framed
            # inside another surface (the AI Assistant preview rail/dialog).
            @embedded_preview = ActiveModel::Type::Boolean.new.cast(params[:embed])
            if params.dig(:page, :configuration).present?
              @page    = build_preview_page(params[:page][:configuration])
              @content = PageContentGenerator.new(@page).generate
            else
              @content = @page.content.presence || @page.generate_content
            end
            render template: "admin/maintenance/pages/preview", layout: "preview"
          end
          format.json do
            content = if params.dig(:page, :configuration).present?
                        PageContentGenerator.new(build_preview_page(params[:page][:configuration])).generate
            else
                        @page.content.presence || @page.generate_content
            end
            render json: { content: content }
          end
        end
      end

      def find_page
        @page = definition_scope(Page).find(params[:page_id])
      end

      def build_preview_page(configuration_json_string)
        preview_page = @page.dup
        preview_page.configuration = configuration_json_string
        # Clear the parsed-config memo (the raw `configuration=` setter does not),
        # so the preview reflects the submitted config rather than the saved one.
        preview_page.instance_variable_set(:@configuration_json_parsed, nil)
        preview_page.readonly!
        preview_page
      end

      def resolve_form_action_from_params
        return nil unless @page&.public_uuid.present?

        public_page_submit_path(customer_id: params[:customer_id], uuid: @page.public_uuid)
      end
    end
  end
end
