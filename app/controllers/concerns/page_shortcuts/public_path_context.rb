# frozen_string_literal: true

module PageShortcuts
  module PublicPathContext
    extend ActiveSupport::Concern

    included do
      around_action :with_page_shortcut_paths
    end

    private

    def with_page_shortcut_paths(&action)
      PublicPath.with_lookup(customer_id: current_customer_id, host: request.host, &action)
    end
  end
end
