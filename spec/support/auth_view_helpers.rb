# frozen_string_literal: true

# Helper for view specs under spec/views/authentication/*.
# Devise view helpers (resource, resource_name, devise_mapping) and the
# app's custom current_customer_id helper are not declared on
# ActionView::Base, so stubbing them under verify_partial_doubles requires
# the without_partial_double_verification wrapper. This module centralizes
# that boilerplate so new auth-view specs stay small.
module AuthViewHelpers
  def stub_devise_view_context(resource, customer)
    assign(:resource, resource)
    controller.request.path_parameters[:customer_id] = customer.id.to_s
    without_partial_double_verification do
      allow(view).to receive(:resource).and_return(resource)
      allow(view).to receive(:resource_name).and_return(:user)
      allow(view).to receive(:current_customer).and_return(customer)
      allow(view).to receive(:current_customer_id).and_return(customer.id)
      allow(view).to receive(:devise_mapping).and_return(Devise.mappings[:user])
    end
  end
end

RSpec.configure do |config|
  config.include AuthViewHelpers, type: :view
end
