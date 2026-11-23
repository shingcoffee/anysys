# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  class IndustryTemplatesController < ApplicationController
    dashboard_menu_item :maintenance
    before_action :set_industry, only: %i[show edit update]

    def index
      @industry_groups = Customer::INDUSTRY_GROUPS
      @mapping_counts = IndustryTemplateMapping.group(:industry).count
      @total_templates = PageLayoutTemplates.keys.size
    end

    def show
      mapped_keys = IndustryTemplateMapping.template_keys_for(@industry)
      render json: { industry: @industry, template_keys: mapped_keys }
    end

    def edit
      @templates = PageLayoutTemplates.all
      @categories = PageLayoutTemplates.categories.except("all")
      @mapped_keys = IndustryTemplateMapping.template_keys_for(@industry)
    end

    def update
      raw = params[:template_keys]
      keys = raw.nil? ? [] : Array.wrap(raw)
      unless (raw.nil? || raw.is_a?(Array) || raw.is_a?(String)) && keys.all? { |key| key.is_a?(String) }
        return invalid_template_keys
      end
      template_keys = keys.reject(&:blank?).uniq

      IndustryTemplateMapping.replace_for_industry!(@industry, template_keys)

      redirect_to admin_maintenance_platform_industry_templates_path(current_customer_id),
                  notice: t("maint_platform.flash.industry_templates.mappings_updated", industry: Customer.industry_label_for(@industry))
    rescue ActiveRecord::RecordInvalid
      invalid_template_keys
    end

    private

    def invalid_template_keys
      message = t("maint_platform.flash.industry_templates.invalid_template_keys")
      respond_to do |format|
        format.html { redirect_to edit_admin_maintenance_platform_industry_template_path(current_customer_id, @industry), alert: message }
        format.json { render json: { errors: [message] }, status: :unprocessable_entity }
      end
    end

    def set_industry
      @industry = params[:id].to_s
      return if Customer.industries.key?(@industry)

      respond_to do |format|
        format.json { render json: { error: t("maint_platform.flash.industry_templates.invalid_industry", industry: @industry) }, status: :not_found }
        format.html { redirect_to admin_maintenance_platform_industry_templates_path(current_customer_id), alert: t("maint_platform.flash.industry_templates.invalid_industry", industry: @industry) }
      end
    end
  end
end
end
end
