# frozen_string_literal: true

module Admin
  module Maintenance
    class EntityVersionsController < BaseVersionsController
      # accessible = own customer's entities OR shared entities, so a customer can
      # view/manage their own override history of a shared entity.
      versioned_resource finder: -> { definition_scope(Entity).find(params[:entity_id]) },
                         ivar: :@entity

      def index
        versions = versions_for_index.recent.includes(:based_on_version)
        pages_by_version = Page.generated_from_entity_line(generated_page_owner_id, parent)
                               .pluck(:entity_version_id, :id)
                               .to_h
        render json: versions.map { |v|
          index_json(v).merge(generated_page_id: pages_by_version[v.id], writable: index_line_writable?)
        }
      end

      # GET .../versions/:id/edit — redirect to the entity editor for this version.
      def edit
        version = line_version
        redirect_to edit_admin_maintenance_entity_path(current_customer_id, @entity, version: version.id)
      end

      def create
        id = params.require(:version_id)
        raise ActiveRecord::RecordNotFound unless (id.is_a?(String) || id.is_a?(Integer)) && id.to_s.match?(/\A[1-9]\d*\z/)

        version = parent.current_line_versions.find(id)
        result = ::Entities::PromoteVersion.call(entity: parent, version: version, restore: true)
        return promotion_failure(result) unless result.success?

        render json: { success: true, version_number: result.version.version_number }
      end

      def default
        result = ::Entities::PromoteVersion.call(entity: parent, version: line_version)
        return promotion_failure(result) unless result.success?

        render json: { success: true, default_version_id: result.version.id, version_number: result.version.version_number }
      end

      # POST .../versions/:id/page — create a page from this version snapshot.
      def page
        result = ::Pages::Activities::CreateFromEntityVersion.call(
          entity: @entity,
          version: line_version,
          customer: current_customer,
          shared: shared_resources_mode?
        )
        if result.success?
          render json: {
            success: true,
            page_id: result.page.id,
            url: page_detail_url(result.page)
          }
        else
          render json: { error: result.error_code, message: result.message },
                 status: :unprocessable_content
        end
      end

      private

      def promotion_failure(result)
        errors = Array(result.errors).presence || [t("routes_audit.version_promotion_failed")]
        render json: { success: false, errors: errors }, status: :unprocessable_entity
      end

      def generated_page_owner_id
        shared_resources_mode? ? nil : current_customer_id
      end

      # Tenant override history, or the global default line when this customer
      # has not forked the shared entity yet — Create page needs those ids.
      def versions_for_index
        return @versions_for_index if defined?(@versions_for_index)

        line = parent.current_line_versions
        if parent.shared? && !shared_resources_mode? && !line.exists?
          @index_line_writable = false
          @versions_for_index = parent.versions_relation.where(customer_id: nil)
        else
          @index_line_writable = true
          @versions_for_index = line
        end
      end

      def index_line_writable?
        versions_for_index
        @index_line_writable
      end

      # Read + Create page may use the global snapshot of a shared entity.
      # Set-default / delete stay on the tenant line so a customer URL cannot
      # mutate Shared Resources.
      def line_version
        if action_name.in?(%w[default destroy])
          parent.current_line_versions.find(params[:id])
        else
          parent.current_line_versions.find_by(id: params[:id]) ||
            shared_global_version ||
            raise(ActiveRecord::RecordNotFound)
        end
      end

      def shared_global_version
        return unless parent.shared?

        parent.versions_relation.where(customer_id: nil).find_by(id: params[:id])
      end

      def page_detail_url(record)
        if shared_resources_mode?
          admin_maintenance_platform_page_path(current_customer_id, record)
        else
          admin_maintenance_page_path(current_customer_id, record)
        end
      end
    end
  end
end
