# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard search", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer, role: :admin) }
  let(:admin)    { user }
  let(:guard_path) { "/#{customer.id}/admin/search" }

  it_behaves_like "an admin-guarded GET"

  before { sign_in user }

  def do_search(q)
    get "/#{customer.id}/admin/search",
        params: { q: q },
        headers: { "Accept" => "application/json" }
  end

  it "returns JSON with a groups array" do
    create(:page, customer: customer, name: "Invoice Draft")
    do_search("invoice")
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    body = JSON.parse(response.body)
    expect(body["query"]).to eq("invoice")
    expect(body["groups"].map { |g| g["key"] }).to include("pages")
  end

  it "returns empty groups for a short query" do
    create(:page, customer: customer, name: "Invoice Draft")
    do_search("i")
    body = JSON.parse(response.body)
    expect(body["groups"]).to eq([])
  end

  it "scopes results to the current customer" do
    other_customer = create(:customer)
    create(:page, customer: other_customer, name: "Invoice Draft")
    do_search("invoice")
    body = JSON.parse(response.body)
    expect(body["groups"]).to eq([])
  end

  it "includes shared pages the tenant can open" do
    create(:page, :shared, name: "Invoice Blueprint")
    do_search("invoice")
    body = JSON.parse(response.body)
    labels = body["groups"].flat_map { |g| g["items"].map { |i| i["label"] } }
    expect(labels).to include("Invoice Blueprint")
  end

  it "localizes group labels for the active locale" do
    create(:page, customer: customer, name: "Invoice Draft")
    user.update_column(:locale, "zh-CN")
    do_search("invoice")
    body = JSON.parse(response.body)
    expect(body["groups"].map { |g| g["label"] }).to include("页面")
  end
end
