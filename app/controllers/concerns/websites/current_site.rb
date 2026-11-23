# frozen_string_literal: true

module Websites
  # Shared tenant website lookup for public + admin controllers.
  module CurrentSite
    extend ActiveSupport::Concern

    included do
      helper_method :current_website if respond_to?(:helper_method)
    end

    private

    def current_website
      return @current_website if defined?(@current_website)

      @current_website = Website.find_by(customer_id: current_customer_id)
    end

    def website_module_enabled?
      FeatureModules::Website::Registration.enabled_for?(current_customer_id)
    end

    def website_pages_scope
      WebsitePage.for_current_customer
    end

    def call_website_activity(name, **kwargs)
      "Websites::Activities::#{name}".constantize.call(**kwargs)
    end

    def website_activity_ok?(result)
      return false if result.nil?

      result.respond_to?(:success?) ? result.success? : true
    end
  end
end
