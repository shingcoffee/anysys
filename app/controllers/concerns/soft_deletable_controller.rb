# frozen_string_literal: true

# SoftDeletableController
#
# Provides soft delete functionality (trash, restore, empty_trash) for controllers.
# Works with tenant-scoped resources when TenantContext is included.
#
# Usage:
#   class FlowchartsController < ApplicationController
#     include SoftDeletableController
#
#     soft_deletable Flowchart
#   end
#
module SoftDeletableController
  extend ActiveSupport::Concern

  included do
    class_attribute :soft_deletable_resource_class
    class_attribute :soft_deletable_resource_name
  end

  class_methods do
    def soft_deletable(resource_class, resource_name: nil)
      self.soft_deletable_resource_class = resource_class
      self.soft_deletable_resource_name = resource_name || resource_class.name.underscore
    end
  end

  # GET /:customer_id/resources/trash
  def trash
    result = ModuleEntriesResolver.call(
      scope: scoped_deleted_resources.order(updated_at: :desc),
      columns: [ { key: :updated_at, sortable: false, searchable: false } ],
      params: params.permit(:page, :per_page).to_h.symbolize_keys
    )
    @resources = result[:rows]
    @pagination = result[:pagination]
    instance_variable_set("@#{soft_deletable_resource_name.pluralize}", @resources)
  end

  # DELETE /:customer_id/resources/empty_trash
  def empty_trash
    scope = scoped_deleted_resources
    deleted_count = scope.count
    # destroy_all (not delete_all) so dependent: :destroy fires — versioned
    # resources (Entity/Flowchart/Page) have version rows whose FK to the parent
    # would otherwise block a raw delete.
    scope.destroy_all
    redirect_to soft_deletable_trash_path,
                notice: t("common.flash.permanently_deleted", count: deleted_count, resource: empty_trash_resource_label)
  end

  private

  def empty_trash_resource_label
    t("common.flash.resources.#{soft_deletable_resource_name}",
      default: soft_deletable_resource_class.name.downcase)
  end

  # Returns deleted resources scoped to the current tenant
  # For Customer resource (which doesn't have customer_id), returns all deleted
  def scoped_deleted_resources
    if soft_deletable_resource_class == Customer
      soft_deletable_resource_class.only_deleted
    elsif respond_to?(:tenant_set?, true) && tenant_set?
      soft_deletable_resource_class.only_deleted.where(customer_id: current_customer_id)
    else
      soft_deletable_resource_class.only_deleted
    end
  end

  # Override URL generation for resources that need different path patterns
  def soft_deletable_index_url
    if soft_deletable_resource_class == Customer
      admin_maintenance_platform_customers_url(current_customer_id)
    else
      send("admin_maintenance_#{soft_deletable_resource_name.pluralize}_url", current_customer_id)
    end
  end

  def soft_deletable_trash_path
    if soft_deletable_resource_class == Customer
      trash_admin_maintenance_platform_customers_path(current_customer_id)
    else
      send("trash_admin_maintenance_#{soft_deletable_resource_name.pluralize}_path", current_customer_id)
    end
  end
end
