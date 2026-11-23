# frozen_string_literal: true

module Pages
  # Picks a free page action key for a tenant. Trashed and shared pages count
  # as taken: a restored page must not collide, and a tenant key would shadow
  # a shared one.
  module ActionKeys
    module_function

    def taken?(key, customer_id:)
      Page.unscoped.where(customer_id: [customer_id, nil]).exists?(action_key: key)
    end

    def unique(base, customer_id:)
      (1..).lazy.map { |attempt| attempt == 1 ? base : "#{base}_#{attempt}" }
           .find { |key| !taken?(key, customer_id: customer_id) }
    end
  end
end
