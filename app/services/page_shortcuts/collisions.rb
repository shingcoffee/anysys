# frozen_string_literal: true

module PageShortcuts
  module Collisions
    module_function

    # Both writers reserve the same tenant-relative paths. Keep the customer
    # lock until validation, generated slugs and all writes have completed.
    def with_customer_lock(customer_id:)
      Customer.transaction(requires_new: true) do
        Customer.lock.find(customer_id)
        yield
      end
    end

    # Reserve unpublished inner slugs too, so publishing cannot take an alias.
    # Root is intentionally overrideable by any eligible explicit destination.
    def automatic_page(path:, customer_id:)
      return if path == "/" || !PathPolicy.automatic?(path)

      WebsitePage.joins(:website).where(customer_id: customer_id, home: false,
                                      slug: path.delete_prefix("/"),
                                      websites: { customer_id: customer_id }).pick(:id)
    end

    def shortcut_conflict?(path:, customer_id:, target_type:, target_id:)
      id = automatic_page(path: path, customer_id: customer_id)
      id.present? && !same_website_target?(target_type: target_type, target_id: target_id, page_id: id)
    end

    def website_slug_taken?(slug:, customer_id:, page_id: nil)
      path = "/#{slug}"
      return false unless PathPolicy.automatic?(path) && path != "/"

      shortcut = PageShortcut.for_customer(customer_id).where(path: path).pick(:target_type, :target_id)
      shortcut.present? && !same_website_target?(target_type: shortcut[0], target_id: shortcut[1], page_id: page_id)
    end

    def same_website_target?(target_type:, target_id:, page_id:)
      page_id.present? && target_type == "WebsitePage" && target_id.to_i == page_id
    end
  end
end
