# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::Authentication::Events", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/modules/authentication/events" }

  it_behaves_like "an admin-guarded GET"

  def create_event(cust_id, **over)
    Authentication::Event.create!(
      { customer_id: cust_id, event: "login_succeeded", ip: "203.0.113.9" }.merge(over)
    )
  end

  it "lists the tenant's own events" do
    create_event(customer.id, ip: "198.51.100.7")
    get "/#{customer.id}/admin/modules/authentication/events"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("198.51.100.7")
  end

  it "does not surface another tenant's events" do
    other = create(:customer)
    create_event(other.id, ip: "10.9.9.9")
    get "/#{customer.id}/admin/modules/authentication/events"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("10.9.9.9")
  end

  it "filters by event kind" do
    create_event(customer.id, event: "login_failed", ip: "1.1.1.1")
    create_event(customer.id, event: "logout", ip: "2.2.2.2")
    get "/#{customer.id}/admin/modules/authentication/events", params: { event: "login_failed" }
    expect(response.body).to include("1.1.1.1")
    expect(response.body).not_to include("2.2.2.2")
  end

  it "localizes oauth_authorized instead of dumping a humanized key" do
    create_event(customer.id, event: "oauth_authorized", ip: "203.0.113.50")
    get "/#{customer.id}/admin/modules/authentication/events"
    expect(response.body).to include(I18n.t("admin_modules.authentication.events.kinds.oauth_authorized"))
    expect(response.body).not_to include("Oauth authorized")
  end

  it "localizes oauth_authorized in zh-CN" do
    create_event(customer.id, event: "oauth_authorized", ip: "203.0.113.51")
    get "/#{customer.id}/admin/modules/authentication/events", params: { locale: "zh-CN" }
    expect(response.body).to include(
      I18n.t("admin_modules.authentication.events.kinds.oauth_authorized", locale: :"zh-CN")
    )
  end
end
