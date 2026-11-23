# frozen_string_literal: true

module Admin
  module Settings
    class MemberSourcesController < ApplicationController
      dashboard_menu_item :settings

      before_action :load_source

      def show
        @source_name = @source.name
        @editable    = @source.editable?
        @rows        = ::Member::Surfaces.surfaces_in(
          source_key: @source.key, customer: current_customer
        ).map { |effective| ::Admin::Settings::MemberRowPresenter.new(effective: effective) }
      end

      def update
        return head(:forbidden) unless @source.editable?

        result = ::Member::Settings::Operation::Update.call(
          customer: current_customer,
          params:   params.fetch(:member_settings, {})
        )
        if result.success?
          redirect_to "/#{current_customer.id}/admin/settings/member/sources/#{@source.key}",
                      notice: t("admin_settings.flash.member_sources.saved")
        else
          show
          render :show, status: :unprocessable_entity
        end
      end

      private

      def load_source
        @source = ::Member::Surfaces.source_for(params[:key]) or raise ActiveRecord::RecordNotFound
      end
    end
  end
end
