# frozen_string_literal: true

module Admin
module Maintenance
  class ConstantsController < ApplicationController
    include Listable
    include SharedResourceMode
    dashboard_menu_item :maintenance
    before_action :find_constant, only: %i[show edit update destroy]
    guard_shared_global_writes :@constant, only: :destroy, json_error: -> { t("maint_core.flash.constants.shared_readonly_message") } do
      admin_maintenance_constants_path(current_customer_id)
    end

    def index
      respond_to do |format|
        format.html do
          @columns = [
            { key: :name,            label: I18n.t("common.labels.name"),    sortable: true, searchable: true },
            { key: :options_count,    label: I18n.t("common.labels.options"), type: :number, sortable: false, searchable: false,
              cell: ->(c) { c.options.size } },
            { key: :options_preview,  label: I18n.t("common.labels.preview"), type: :truncate, sortable: false, searchable: false,
              cell: ->(c) { c.options.first(5).map(&:to_s).join(", ") } },
            { key: :updated_at,       label: I18n.t("common.labels.updated_at"), type: :datetime, sortable: true }
          ]

          result      = listable(definition_scope(Constant).ordered, columns: @columns)
          @rows       = result[:rows]
          @pagination = result[:pagination]
        end

        # The "Use Constant" attribute picker consumes this branch and needs the
        # COMPLETE accessible set (this customer's constants + every shared one),
        # so it is intentionally unpaginated — pagination here could push shared
        # constants out of reach for a tenant with many of its own.
        format.json do
          render json: definition_scope(Constant).ordered.as_json(only: %i[id name options])
        end
      end
    end

    def show
      respond_to do |format|
        format.html
        format.json { render json: @constant }
      end
    end

    def new
      @constant = Constant.new
    end

    def edit
    end

    def create
      @constant = Constant.new(constant_params)
      apply_create_identity!(@constant)

      if @constant.save
        respond_to do |format|
          format.html { redirect_to admin_maintenance_constants_path(current_customer_id), notice: t("maint_core.flash.constants.created") }
          format.json { render json: @constant, status: :created }
        end
      else
        respond_to do |format|
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: { errors: @constant.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    def update
      if @constant.update(constant_params)
        # Reflect every Save in the "last updated" time. Rails only bumps
        # updated_at when an attribute actually changed; an identical resubmit
        # would otherwise leave the timestamp stale, so touch when nothing else
        # moved it. Tenant-path overrides must not touch the shared parent row.
        unless tenant_override?(@constant)
          @constant.touch unless @constant.saved_change_to_updated_at?
        end

        respond_to do |format|
          format.html { redirect_to admin_maintenance_constant_path(current_customer_id, @constant), notice: t("maint_core.flash.constants.updated") }
          format.json { render json: @constant }
        end
      else
        respond_to do |format|
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: { errors: @constant.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      @constant.destroy

      respond_to do |format|
        format.html { redirect_to admin_maintenance_constants_path(current_customer_id), notice: t("maint_core.flash.constants.deleted") }
        format.json { head :no_content }
      end
    end

    private

    def find_constant
      @constant = definition_scope(Constant).find(params[:id])
    end

    def constant_params
      raw = params.require(:constant)

      permitted = raw.permit(:name).to_h
      # Only set options when the parameter is explicitly present. On update,
      # a missing options key must leave the existing array intact; a blank
      # or malformed value is normalized to [] and will fail validation.
      permitted[:options] = normalize_options(raw[:options]) if raw.key?(:options)

      permitted
    end

    def normalize_options(raw_options)
      return [] if raw_options.blank?

      if raw_options.is_a?(String)
        return [] if raw_options.strip.empty?

        begin
          parsed = JSON.parse(raw_options)
          parsed.is_a?(Array) ? parsed : []
        rescue JSON::ParserError
          []
        end
      elsif raw_options.is_a?(ActionController::Parameters)
        raw_options.values
      elsif raw_options.is_a?(Array)
        raw_options
      else
        []
      end
    end
  end
end
end
