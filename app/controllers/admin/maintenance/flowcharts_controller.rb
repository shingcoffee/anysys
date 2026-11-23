# frozen_string_literal: true

module Admin
module Maintenance
  class FlowchartsController < ApplicationController
    dashboard_menu_item :maintenance
    include SoftDeletableController
    include Listable
    include SharedResourceMode

    soft_deletable Flowchart

    before_action :find_flowchart, only: [:show, :edit, :update, :destroy]
    # Tenant-path edits of a shared flowchart fork a per-customer override
    # (including for 81721200). Destroying a shared flowchart is Shared
    # Resources (path) only.
    guard_shared_global_writes :@flowchart, only: :destroy, json_error: "shared_flowchart_readonly" do
      admin_maintenance_flowcharts_path(current_customer_id)
    end

    def index
      @columns = [
        { key: :name,            label: I18n.t("common.labels.name"),     sortable: true, searchable: true },
        { key: :elements_count,  label: I18n.t("common.labels.elements"), type: :number, sortable: false, searchable: false,
          cell: ->(f) { f.elements.length } },
        { key: :current_version,  label: I18n.t("common.labels.current_version"), type: :text, sortable: false, searchable: false,
          cell: ->(f) { (v = f.display_current_version) ? "v#{v.version_number}" : I18n.t("common.labels.em_dash") } },
        { key: :updated_at,      label: I18n.t("common.labels.updated_at"),  type: :datetime, sortable: true }
      ]
      scope  = definition_scope(Flowchart).includes(:flowchart_versions, current_version: :content)
      result = listable(scope, columns: @columns)
      @rows = result[:rows]
      @flowcharts = @rows
      @pagination = result[:pagination]

      respond_to do |format|
        format.html
        format.json do
          except_id = params[:except_id]
          flowcharts = except_id.present? ? definition_scope(Flowchart).recent.except_id(except_id) : definition_scope(Flowchart).recent
          flowcharts_with_elements = flowcharts.select { |f| f.elements.any? }
          render json: flowcharts_with_elements.map { |f|
            {
              id: f.id,
              name: f.name,
              description: f.description,
              elements_count: f.elements.length,
              shared: f.shared?,
              updated_at: f.updated_at.iso8601
            }
          }
        end
      end
    end

    def show
      respond_to do |format|
        format.html do
          @bound_pages = Page.preload_entities(@flowchart.pages.where(customer_id: [design_customer_id, nil].uniq).by_name.to_a)
        end
        format.json do
          render json: {
            id: @flowchart.id,
            name: @flowchart.name,
            description: @flowchart.description,
            configuration: @flowchart.configuration,
            shared: @flowchart.shared?,
            updated_at: @flowchart.updated_at.iso8601
          }
        end
      end
    end

    def new
      @flowchart = Flowchart.new_with_defaults(name: "")
      apply_create_identity!(@flowchart)
    end

    def create
      @flowchart = Flowchart.new_with_defaults(flowchart_params)
      apply_create_identity!(@flowchart)

      if @flowchart.save
        redirect_to edit_admin_maintenance_flowchart_path(current_customer_id, @flowchart), notice: t("maint_core.flash.flowcharts.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @design_entity = ::Flowcharts::DesignEntity.for(@flowchart, customer_id: design_customer_id)
    end

    def update
      # The head check and the save share one transaction on a freshly loaded
      # record: a draft head is revised in place, so a save racing past the
      # check would overwrite the other save with no version left behind.
      saved = Flowchart.transaction do
        @flowchart = definition_scope(Flowchart).lock.find(@flowchart.id)
        next :conflict if stale_head?

        @flowchart.commit_based_on_version_id = explicit_based_on_version_id
        @flowchart.update(update_params)
      end
      return render_head_conflict if saved == :conflict

      if saved
        # A version snapshot (when the configuration changed) is created
        # automatically by Versionable's after_save auto-commit.
        respond_to do |format|
          format.html { redirect_to admin_maintenance_flowchart_path(current_customer_id, @flowchart), notice: t("maint_core.flash.flowcharts.updated") }
          format.json do
            render json: { status: "success", message: t("maint_core.flash.flowcharts.saved_json"),
                           version_id: @flowchart.current_line_head_version_id,
                           head_revision: @flowchart.current_line_head_revision }
          end
        end
      else
        respond_to do |format|
          format.html do
            @design_entity = ::Flowcharts::DesignEntity.for(@flowchart, customer_id: design_customer_id)
            render :edit, status: :unprocessable_entity
          end
          format.json { render json: { status: "error", errors: @flowchart.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      if @flowchart.soft_delete
        redirect_to admin_maintenance_flowcharts_path(current_customer_id), notice: t("maint_core.flash.flowcharts.deleted")
      else
        redirect_to admin_maintenance_flowcharts_path(current_customer_id), alert: @flowchart.errors.full_messages.to_sentence
      end
    end

    private

    def find_flowchart
      @flowchart = definition_scope(Flowchart).find(params[:id])
    end

    # The editor sends the line head it loaded; any other head means another
    # tab or user saved since, so this save would silently discard their work.
    # A draft head is revised in place, so its revision is compared as well.
    def stale_head?
      return false unless params.key?(:expected_head_version_id)

      params[:expected_head_version_id].to_s != @flowchart.current_line_head_version_id.to_s ||
        params[:expected_head_revision].to_s != @flowchart.current_line_head_revision.to_s
    end

    def render_head_conflict
      message = t("maint_core.flash.flowcharts.save_conflict")
      respond_to do |format|
        format.html { redirect_back_or_to edit_admin_maintenance_flowchart_path(current_customer_id, @flowchart), alert: message }
        format.json do
          render json: { status: "conflict", message: message, head_version_id: @flowchart.current_line_head_version_id,
                         head_revision: @flowchart.current_line_head_revision },
                 status: :conflict
        end
      end
    end

    # A based-on id equal to the head is not new lineage; passing it through
    # would bypass Versionable's unchanged-payload no-op and snapshot every save.
    def explicit_based_on_version_id
      based_on = params[:based_on_version_id]
      based_on unless based_on.to_s == @flowchart.current_line_head_version_id.to_s
    end

    def flowchart_params
      keys = tenant_override?(@flowchart) ? %i[configuration] : %i[name description configuration template]
      params.require(:flowchart).permit(*keys)
    end

    # Pages count toward the editor only within the owner being edited:
    # Shared Resources sees shared pages, a tenant its own and the shared ones.
    def design_customer_id = shared_resources_mode? ? nil : current_customer_id

    def update_params
      keys = tenant_override?(@flowchart) ? %i[configuration] : %i[name description configuration]
      params.require(:flowchart).permit(*keys)
    end
  end
end
end
