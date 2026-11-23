# frozen_string_literal: true

module Admin
  module Settings
    class MemberSurfacesController < ApplicationController
      dashboard_menu_item :settings

      before_action :load_surface

      def show
        @presenter = ::Admin::Settings::MemberRowPresenter.new(effective: @effective)
      end

      def update
        return head(:forbidden) unless @source.editable?

        result = ::Member::Settings::Operation::Update.call(
          customer: current_customer,
          params:   member_settings_params
        )
        if result.success?
          redirect_to "/#{current_customer.id}/admin/settings/member/sources/#{@source.key}/surfaces/#{@effective.key}",
                      notice: t("admin_settings.flash.member_surfaces.saved")
        else
          @presenter = ::Admin::Settings::MemberRowPresenter.new(effective: @effective)
          @form_errors = surface_form_errors(result)
          render :show, status: :unprocessable_entity
        end
      end

      private

      MEMBER_SETTINGS_ROW = [
        :surface_key, :enabled, :position, :label, :icon, :subtitle,
        :empty_headline, :empty_body, :per_page,
        :row_action_key, :row_action_field, :row_action_label,
        { visible_column_keys: [] },
        { visible_detail_row_keys: [] },
        { visible_section_keys: [] }
      ].freeze

      def member_settings_params
        raw = params[:member_settings]
        return {} unless raw.is_a?(ActionController::Parameters)

        raw.permit(rows: MEMBER_SETTINGS_ROW)
      end

      # Reform nests collection errors as rows.0.field; the form component
      # reads field-level keys (row_action_key, …).
      def surface_form_errors(result)
        messages = result.errors&.messages
        return if messages.blank?

        messages.each_with_object({}) do |(key, values), hash|
          field = key.to_s.sub(/\Arows(?:\.\d+)?\./, "").to_sym
          hash[field] = values
        end
      end

      def load_surface
        @source = ::Member::Surfaces.source_for(params[:source_key]) or raise ActiveRecord::RecordNotFound
        @effective = ::Member::Surfaces.fetch(params[:key], customer: current_customer)
        raise ActiveRecord::RecordNotFound unless @effective.source_key == @source.key.to_sym
      end
    end
  end
end
