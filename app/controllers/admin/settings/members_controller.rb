# frozen_string_literal: true

module Admin
  module Settings
    # Admin page — /:cid/admin/settings/member
    # Hub listing all member surface sources (Builtin, Modules, Entities).
    class MembersController < ApplicationController
      dashboard_menu_item :settings

      def show
        @hub_cards = ::Member::Surfaces.sources.map do |source_class|
          ::Admin::Settings::MemberHubCardPresenter.new(
            source_class: source_class,
            customer:     current_customer
          )
        end
      end

      def update
        result = ::Member::Settings::Operation::Update.call(
          customer: current_customer,
          params:   params.fetch(:member_settings, {})
        )
        if result.success?
          redirect_to "/#{current_customer.id}/admin/settings/member",
                      notice: t("admin_settings.flash.members.saved")
        else
          @hub_cards = []
          flash.now[:alert] = result.errors.full_messages.join(", ") if result.errors.respond_to?(:full_messages)
          render :show, status: :unprocessable_entity
        end
      end
    end
  end
end
