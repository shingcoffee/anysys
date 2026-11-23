# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      class IndustryTemplateAssignmentsController < ApplicationController
        dashboard_menu_item :maintenance
        before_action :set_industry

        def create
          mapping = IndustryTemplateMapping.new(industry: @industry, template_key: params[:template_key])

          if mapping.save
            render json: {
              status:       "added",
              template_key: mapping.template_key,
              count:        IndustryTemplateMapping.for_industry(@industry).count
            }
          else
            render json: { errors: mapping.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def destroy
          template_key = params[:id].presence || params[:template_key]
          mapping = IndustryTemplateMapping.find_by(industry: @industry, template_key: template_key)

          if mapping&.destroy
            render json: {
              status:       "removed",
              template_key: template_key,
              count:        IndustryTemplateMapping.for_industry(@industry).count
            }
          else
            render json: { error: t("maint_platform.flash.industry_templates.mapping_not_found") }, status: :not_found
          end
        end

        private

        def set_industry
          @industry = params[:industry_template_id].to_s
          return if Customer.industries.key?(@industry)

          render json: { error: t("maint_platform.flash.industry_templates.invalid_industry", industry: @industry) }, status: :not_found
        end
      end
    end
  end
end
