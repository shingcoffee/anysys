# frozen_string_literal: true

module Admin
  module Maintenance
    class ConstantCopiesController < ApplicationController
      include SharedResourceMode
      dashboard_menu_item :maintenance

      def show
        source = definition_scope(Constant).find(params[:constant_id])
        require_copyable_source!(source)
        @constant = Constant.new(
          name: I18n.t("maint_core.entities.copy_name", name: source.name),
          options: source.options.dup
        )
        apply_create_identity!(@constant)
        render "admin/maintenance/constants/new"
      end
    end
  end
end
