# frozen_string_literal: true

# Per-customer head pointer for a shared flowchart: the current override
# version customer `customer_id` sees for `flowchart`. One row per
# (flowchart, customer); absence means the customer follows the flowchart's
# global default version.
class FlowchartCustomerHead < ApplicationRecord
  belongs_to :flowchart
  belongs_to :current_version, class_name: "FlowchartVersion"

  validates :customer_id, presence: true, uniqueness: { scope: :flowchart_id }
end
