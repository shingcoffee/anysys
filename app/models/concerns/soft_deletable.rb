# frozen_string_literal: true

# Provides soft delete functionality for ActiveRecord models.
#
# This concern adds status-based soft deletion with support for:
# - Scoping to only active records by default
# - Soft delete and restore methods
# - Class methods to query deleted or all records
#
# Usage:
#   class MyModel < ApplicationRecord
#     include SoftDeletable
#     soft_deletable deleted_status: :deleted  # or :inactive
#   end
#
module SoftDeletable
  extend ActiveSupport::Concern

  included do
    class_attribute :soft_delete_status, default: :deleted

    scope :visible, -> { where(status: soft_delete_active_status) }
  end

  class_methods do
    # Configure soft delete behavior
    #
    # @param deleted_status [Symbol] The status value representing deleted records
    def soft_deletable(deleted_status: :deleted)
      self.soft_delete_status = deleted_status
    end

    # Get the status value for active records
    def soft_delete_active_status
      :active
    end

    # Query including deleted records (bypasses default scope)
    def with_deleted
      unscope(where: :status)
    end

    # Query only deleted records
    def only_deleted
      unscope(where: :status).where(status: soft_delete_status)
    end
  end

  # Mark record as deleted (soft delete)
  def soft_delete
    update(status: self.class.soft_delete_status)
  end

  # Restore a deleted record
  def restore
    update(status: self.class.soft_delete_active_status)
  end

  # Check if record is deleted
  def deleted?
    return false if status.nil?

    status.to_s == self.class.soft_delete_status.to_s
  end

  # Check if record is active
  def active?
    return false if status.nil?

    status.to_s == self.class.soft_delete_active_status.to_s
  end
end
