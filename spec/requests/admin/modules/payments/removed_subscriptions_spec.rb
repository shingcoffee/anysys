# frozen_string_literal: true

require "rails_helper"

# Tenant subscription management lives under admin/settings/billing/*; the
# Payments module no longer exposes its own Subscriptions records surface.
RSpec.describe "admin/modules/payments/subscriptions (removed routes)", type: :request do
  it_behaves_like "a removed admin URL", "/admin/modules/payments/subscriptions"
  it_behaves_like "a removed admin URL", "/admin/modules/payments/subscriptions/new"
  it_behaves_like "a removed admin URL", "/admin/modules/payments/subscriptions/1"

  describe "writes" do
    include_context "as admin"

    it "does not route subscription creation or cancellation" do
      post "/#{customer.id}/admin/modules/payments/subscriptions"
      expect(response).to have_http_status(:not_found)
      post "/#{customer.id}/admin/modules/payments/subscriptions/1/cancellation"
      expect(response).to have_http_status(:not_found)
    end
  end

  it "drops Subscriptions from the Payments module navigation" do
    entries = FeatureModules::Payment::Registration.sidebar_contributions(nil).fetch(:entries)
    expect(entries.map(&:entry_key)).to eq(%w[transactions reconciliations disputes])
  end
end
