# frozen_string_literal: true

module Admin
module Maintenance
  class PagesController < ApplicationController
    dashboard_menu_item :maintenance
    include SoftDeletableController
    include Listable
    include SharedResourceMode

    soft_deletable Page

    before_action :find_page, only: [:show, :edit, :update, :destroy]
    # Tenant-path edits of a shared page fork a per-customer override (including
    # for 81721200). Destroying a shared page is Shared Resources (path) only.
    guard_shared_global_writes :@page, only: :destroy, json_error: "shared_page_readonly" do
      admin_maintenance_pages_path(current_customer_id)
    end

    def index
      @columns = [
        { key: :name,       label: I18n.t("common.labels.name"),       sortable: true, searchable: true },
        { key: :entity_name, label: I18n.t("common.labels.entity"),    sortable: false, searchable: false,
          cell: ->(p) { p.entity&.display_label || I18n.t("common.labels.em_dash") } },
        { key: :launched,   label: I18n.t("common.labels.launched"), type: :badge, sortable: true,
          badge: ->(p) { { variant: p.launched? ? :success : :default, label: p.launched? ? I18n.t("common.labels.yes") : I18n.t("common.labels.no") } },
          cell:  ->(p) { p.launched? ? I18n.t("common.labels.yes") : I18n.t("common.labels.no") } },
        { key: :current_version, label: I18n.t("common.labels.current_version"), type: :text, sortable: false, searchable: false,
          cell: ->(p) { (v = p.display_current_version) ? "v#{v.version_number}" : I18n.t("common.labels.em_dash") } },
        { key: :updated_at,  label: I18n.t("common.labels.updated_at"),   type: :datetime, sortable: true }
      ]
      scope  = definition_scope(Page).includes(:page_versions, current_version: :content)
      result = ModuleEntriesResolver.call(
        scope: scope, columns: @columns,
        params: params.permit(:q, :sort, :dir, :page).to_h.symbolize_keys
      )
      @rows       = result[:rows]
      @pagination = result[:pagination]

      respond_to do |format|
        format.html
        format.json do
          pages = scope.recent
          render json: pages.map { |p|
            {
              id:           p.id,
              name:         p.name,
              description:  p.description,
              fields_count: p.fields.length,
              updated_at:   p.updated_at.iso8601(6)
            }
          }
        end
      end
    end

    def show
      respond_to do |format|
        format.html { @form_status = ::Pages::FormHealth.for([@page])[@page.id] }
        format.json do
          render json: {
            id:            @page.id,
            name:          @page.name,
            description:   @page.description,
            configuration: @page.configuration,
            content:       @page.content,
            updated_at:    @page.updated_at.iso8601(6)
          }
        end
      end
    end

    def new
      @page = Page.new_with_defaults(name: "")
      apply_create_identity!(@page)
      load_entity_options
    end

    def create
      @page = Page.new_with_defaults(page_params)
      apply_create_identity!(@page)

      ::Pages::ConfigurationComposer.call(
        page: @page,
        template_key: params.dig(:page, :layout_template),
        theme_preset_key: params.dig(:page, :theme_preset)
      )

      guard = Billing::Quota::Guard.check(customer: current_customer, item_key: "page")
      unless skip_quota_for_shared_create?(@page) || guard.allowed?
        @page.errors.add(:base, guard.message)
        flash.now[:alert] = guard.message
        load_entity_options
        return render :new, status: :unprocessable_entity
      end

      @page.commit_based_on_version_id = params[:based_on_version_id]
      if @page.save
        # v1 snapshot is created automatically by Versionable's after_save auto-commit.
        redirect_to edit_admin_maintenance_page_path(current_customer_id, @page), notice: t("maint_core.flash.pages.created")
      else
        load_entity_options
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      load_entity_options
    end

    def update
      return render_conflict if stale_client_edit?

      @page.commit_based_on_version_id = params[:based_on_version_id]
      success = Page.transaction do
        unless @page.update(update_params)
          raise ActiveRecord::Rollback
        end
        # The configuration snapshot (if changed) is committed automatically by
        # Versionable's after_save auto-commit on the update above. Do not write
        # generated HTML onto the shared parent row during a tenant override.
        if params.dig(:page, :configuration).present? && !tenant_override?(@page)
          unless @page.update(content: @page.generate_content)
            raise ActiveRecord::Rollback
          end
        end
        true
      end

      if success
        respond_to do |format|
          format.html { redirect_to admin_maintenance_page_path(current_customer_id, @page), notice: t("maint_core.flash.pages.updated") }
          format.json { render json: { status: "success", message: t("maint_core.flash.pages.saved_json"), updated_at: @page.updated_at.iso8601(6) } }
        end
      else
        respond_to do |format|
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: { status: "error", errors: @page.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      @page.soft_delete
      redirect_to admin_maintenance_pages_path(current_customer_id), notice: t("maint_core.flash.pages.deleted")
    end

    private

    def find_page
      @page = definition_scope(Page).find(params[:id])
    end

    def stale_client_edit?
      client_stamp = params.dig(:page, :updated_at).presence
      return true unless client_stamp

      parsed = Time.iso8601(client_stamp) rescue nil
      return true unless parsed

      @page.updated_at > parsed + 0.001.seconds
    end

    def render_conflict
      respond_to do |format|
        format.html { redirect_to edit_admin_maintenance_page_path(current_customer_id, @page), alert: t("maint_core.flash.pages.conflict_html") }
        format.json do
          render json: {
            status:            "conflict",
            message:           t("maint_core.flash.pages.conflict_message"),
            server_updated_at: @page.updated_at.iso8601(6)
          }, status: :conflict
        end
      end
    end

    def page_params
      params.require(:page).permit(*permitted_page_keys)
    end
    alias update_params page_params

    # Tenant-path edits of a shared page may only change the versioned
    # configuration (the edit forks into a per-customer override). Identity
    # columns stay Shared Resources / owner-of-owned-page.
    def permitted_page_keys
      return %i[configuration] if tenant_override?(@page)

      %i[name description configuration entity_id captcha_enabled]
    end

    def load_entity_options
      @entities = (shared_resources_mode? ? Entity.shared : Entity.accessible).by_name
    end

    def find_field_in_page_config(page, field_id)
      page.fields.find { |f| f["id"] == field_id }
    end
  end
end
end
