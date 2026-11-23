# frozen_string_literal: true

# Per-customer head pointer for a shared page: the current override version
# customer `customer_id` sees for `page`. One row per (page, customer);
# absence means the customer follows the page's global default version.
class PageCustomerHead < ApplicationRecord
  belongs_to :page
  belongs_to :current_version, class_name: "PageVersion"

  validates :customer_id, presence: true, uniqueness: { scope: :page_id }
end
