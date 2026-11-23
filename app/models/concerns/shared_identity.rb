# frozen_string_literal: true

# SharedIdentity
#
# Platform Shared Resources (created under Maintenance / Platform) are rows
# with customer_id NULL. Tenant-owned rows have a customer_id. There is no
# separate type / sharing-scope column — identity is customer_id alone.
module SharedIdentity
  extend ActiveSupport::Concern

  included do
    scope :shared, -> { where(customer_id: nil) }
    scope :customer_owned, -> { where.not(customer_id: nil) }
    scope :accessible, lambda {
      if Current.customer?
        where(customer_id: Current.customer_id).or(where(customer_id: nil))
      else
        where(customer_id: nil)
      end
    }
  end

  def shared?
    customer_id.nil?
  end

  def customer_owned?
    customer_id.present?
  end
end
