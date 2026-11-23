# frozen_string_literal: true

module Admin
  module Maintenance
    # Abstract base for versioned-resource version history. Subclasses declare the
    # parent via `versioned_resource`. JSON contract is identical across resources
    # so one Stimulus controller drives all three list pages.
    class BaseVersionsController < ApplicationController
      dashboard_menu_item :maintenance
      include SharedResourceMode
      before_action :find_parent
      before_action :guard_write!, only: %i[create default destroy]

      class_attribute :parent_finder, :parent_ivar

      def self.versioned_resource(finder:, ivar:)
        self.parent_finder = finder
        self.parent_ivar   = ivar
      end

      # GET .../versions  (only the current line: own/global, or this customer's
      # override history for a shared, overridable resource)
      def index
        versions = parent.current_line_versions.recent.includes(:based_on_version)
        render json: versions.map { |v| index_json(v) }
      end

      # GET .../versions/:id  (snapshot for client-side diff)
      def show
        v = line_version
        render json: {
          id: v.id, version_number: v.version_number, description: v.description,
          created_at: v.created_at.iso8601, configuration: v.payload
        }
      end

      # POST .../versions  { version_id: }  (restore-as-new, within the current line)
      def create
        version = parent.current_line_versions.find(params.require(:version_id))
        parent.restore_as_new!(version)
        render json: {
          success: true,
          version_number: parent.current_line_versions.maximum(:version_number),
          configuration: parent.reload.resolved_current_version.content.payload,
          version_id: parent.current_line_head_version_id,
          head_revision: parent.current_line_head_revision
        }
      end

      # PUT .../versions/:id/default  (move the current line's head to an existing version)
      def default
        version = line_version
        parent.set_current_version!(version)
        render json: { success: true, default_version_id: version.id, version_number: version.version_number }
      end

      # DELETE .../versions/:id
      def destroy
        version = line_version
        if version.id == parent.current_line_head_version_id
          return render json: {
            error: "default_version_undeletable",
            message: t("maint_core.errors.versions.current_undeletable")
          }, status: :unprocessable_entity
        end
        owner_cid = version.customer_id
        parent.transaction do
          parent.versions_relation.where(based_on_version_id: version.id).update_all(based_on_version_id: nil)
          version.destroy!
          parent.content_class.sweep_orphans!(customer_id: owner_cid)
        end
        render json: { success: true, id: version.id }
      end

      private

      def parent
        instance_variable_get(parent_ivar)
      end

      def find_parent
        instance_variable_set(parent_ivar, instance_exec(&parent_finder))
      end

      def line_version
        parent.current_line_versions.find(params[:id])
      end

      def index_json(v)
        {
          id: v.id, version_number: v.version_number, description: v.description,
          created_at: v.created_at.iso8601,
          is_default: v.id == parent.current_line_head_version_id,
          based_on_version_number: v.based_on_version_number
        }
      end

      # Overridable in subclasses (flowchart enforces shared/draft guards).
      def guard_write!; end
    end
  end
end
