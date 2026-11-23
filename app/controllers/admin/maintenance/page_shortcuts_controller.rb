# frozen_string_literal: true

module Admin
  module Maintenance
    class PageShortcutsController < ApplicationController
      # ApplicationController's RouteAuthorization authenticates and enforces
      # admin/owner access for every action under this tenant admin prefix.
      dashboard_menu_item :maintenance
      rescue_from ActiveRecord::RecordNotFound do
        head :not_found
      end
      before_action :find_shortcut, only: %i[update destroy]

      def index
        @editing_shortcut = shortcut_scope.find(params[:edit]) if params[:edit].present?
        @form_values = if @editing_shortcut
          { path: @editing_shortcut.path, target: "#{@editing_shortcut.target_type}:#{@editing_shortcut.target_id}" }
        else
          {}
        end
        @errors = []
        prepare_index
      end

      def create
        save_shortcut(PageShortcut.new(customer_id: current_customer_id))
      end

      def update
        save_shortcut(@shortcut)
      end

      def destroy
        result = ::PageShortcuts::Activities::Destroy.call(shortcut: @shortcut, customer_id: current_customer_id)
        if result.success?
          redirect_to admin_maintenance_page_shortcuts_path(current_customer_id),
                      status: :see_other, notice: t("page_shortcuts.flash.deleted")
        else
          @errors = result.errors
          @form_values = {}
          prepare_index
          render :index, status: :unprocessable_entity
        end
      end

      private

      def shortcut_scope
        PageShortcut.where(customer_id: current_customer_id)
      end

      def find_shortcut
        @shortcut = shortcut_scope.find(params[:id])
      end

      def save_shortcut(shortcut)
        @form_values = params.require(:page_shortcut).permit(:path, :target).to_h.symbolize_keys
        result = ::PageShortcuts::Activities::Save.call(
          shortcut: shortcut, params: @form_values, customer_id: current_customer_id
        )

        if result.success?
          redirect_to admin_maintenance_page_shortcuts_path(current_customer_id),
                      status: :see_other, notice: t("page_shortcuts.flash.saved")
        else
          @editing_shortcut = result.model if shortcut.persisted?
          @errors = result.errors
          prepare_index
          render :index, status: :unprocessable_entity
        end
      end

      def prepare_index
        @shortcuts = shortcut_scope.order(:path)
        @available_targets = website_targets + public_page_targets
        @customer_id = current_customer_id
      end

      def website_targets
        ::PageShortcuts::TargetEligibility.website_pages(customer_id: current_customer_id)
                      .order(:position, :id).pluck(:id, :title, :slug, :home).filter_map do |id, title, slug, home|
          next unless home || (slug.is_a?(String) && ::PageShortcuts::PathPolicy::SEGMENT.match?(slug))

          [t("page_shortcuts.destination_label", type: t("page_shortcuts.target_types.website_page"), title: title),
           "WebsitePage:#{id}"]
        end
      end

      def public_page_targets
        ::PageShortcuts::TargetEligibility.public_pages(customer_id: current_customer_id)
                      .order(:name, :id).pluck(:id, :name, :public_uuid).filter_map do |id, name, uuid|
          next if uuid.blank?

          [t("page_shortcuts.destination_label", type: t("page_shortcuts.target_types.public_page"), title: name),
           "Page:#{id}"]
        end
      end
    end
  end
end
