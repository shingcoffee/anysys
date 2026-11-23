# frozen_string_literal: true

# Tenant-stamp Active Storage blobs with customer_id.
#
# Every blob created while a Current.customer is set will inherit that
# customer's id. This is the defensive layer; the authoritative stamp happens
# in the tenant-scoped attachment upload controller (Task 5.4).
#
# The `for_customer` scope is used by the serve/preview controller to enforce
# cross-tenant isolation (a customer admin cannot access another tenant's blob
# even with a leaked signed_id).
Rails.application.config.to_prepare do
  ActiveStorage::Blob.class_eval do
    before_create do
      self.customer_id ||= Current.customer_id if defined?(Current) && Current.customer?
    end

    scope :for_customer, ->(cid) { where(customer_id: cid) }
  end
end
