# frozen_string_literal: true

module Admin
module Maintenance
  # FieldTemplatesController
  #
  # JSON API for managing field templates within a tenant context.
  # All routes are scoped under /:customer_id/maintenance/pages/field_templates
  #
  class FieldTemplatesController < ApplicationController
    dashboard_menu_item :maintenance

  def index
    templates = ::FieldTemplate.for_customer(current_customer_id).order(:name)
    render json: templates.map { |t| template_json(t) }
  end

  def create
    signal, (ctx, _) = FieldTemplates::Create.call([{
      params: template_params.merge(customer_id: current_customer_id)
    }, {}])

    if signal.to_h[:semantic] == :success
      render json: template_json(ctx[:model]), status: :created
    else
      render json: { errors: ctx[:contract]&.errors&.messages || t("maint_core.errors.field_templates.create_failed") }, status: :unprocessable_entity
    end
  end

  def update
    signal, (ctx, _) = FieldTemplates::Update.call([{
      id: params[:id],
      customer_id: current_customer_id,
      params: template_params
    }, {}])

    if signal.to_h[:semantic] == :success
      render json: template_json(ctx[:model])
    else
      render json: { errors: t("maint_core.errors.field_templates.update_failed") }, status: :unprocessable_entity
    end
  end

  def destroy
    signal, (ctx, _) = FieldTemplates::Delete.call([{
      id: params[:id],
      customer_id: current_customer_id
    }, {}])

    if signal.to_h[:semantic] == :success
      head :no_content
    else
      render json: { errors: t("maint_core.errors.field_templates.built_in_undeletable") }, status: :unprocessable_entity
    end
  end

  private

  def template_params
    params.require(:field_template).permit(:name, :category, :description, configuration: {})
  end

  def template_json(t)
    {
      id: t.id,
      name: t.name,
      category: t.category,
      description: t.description,
      configuration: t.configuration,
      built_in: t.built_in
    }
  end
  end
end
end
