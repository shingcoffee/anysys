# frozen_string_literal: true

module Platform
  class ContextBannerComponent < ApplicationComponent
    def render?
      Current.platform_owner_context?
    end

    def customer_name
      Current.acting_as_customer&.name
    end

    def customer_id
      Current.acting_as_customer&.id
    end
  end
end
