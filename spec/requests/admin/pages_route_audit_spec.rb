# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin page runtime batch lifecycle", type: :request do
  include_context "as admin"
  let(:path) { "/#{customer.id}/admin/pages/batch" }
  let(:entity) { create(:entity, customer: customer) }
  let!(:valid_page) do
    create(:page, customer: customer, entity: entity, configuration: {
      "metadata" => {},
      "pages" => [{ "id" => "page_1", "fields" => [{ "id" => "field_1", "field_type" => "text", "label" => "Name" }] }]
    }.to_json)
  end

  it "rolls back the whole batch when any page fails publication preflight" do
    invalid_page = create(:page, customer: customer, entity: entity)

    patch path, params: { ids: [valid_page.id, invalid_page.id], action_key: "launch" }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("success")).to be(false)
    expect(valid_page.reload.launched?).to be(false)
    expect(invalid_page.reload.launched?).to be(false)
  end

  it "does not publish a page bound to an inactive entity" do
    entity.soft_delete

    patch path, params: { ids: [valid_page.id], action_key: "launch" }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(valid_page.reload.launched?).to be(false)
  end

  it "reactivates an inactive owned page and counts only unique accessible rows" do
    valid_page.update_column(:status, Page.statuses[:inactive])
    foreign = create(:page, customer: create(:customer))
    shared = create(:page, :shared)

    patch path, params: { ids: [valid_page.id, valid_page.id, foreign.id, shared.id, 999_999_999], action_key: "activate" }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("success" => true, "count" => 1)
    expect(valid_page.reload).to be_active
    expect(foreign.reload).to be_active
    expect(shared.reload).to be_active
  end

  it "validates a previously launched page before reactivation" do
    invalid = create(:page, customer: customer, entity: entity, launched: true)
    invalid.update_column(:status, Page.statuses[:inactive])

    patch path, params: { ids: [invalid.id], action_key: "activate" }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Page.with_deleted.find(invalid.id)).to be_inactive
  end

  it "returns an invalid result for an unsupported action or malformed selection" do
    patch path, params: { ids: [valid_page.id], action_key: "arbitrary" }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("success")).to be(false)

    patch path, params: { ids: { injected: valid_page.id }, action_key: "deactivate" }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(valid_page.reload).to be_active
  end

  context "with the entity in a domain" do
    let(:domain) { create(:entity_domain, customer: customer, name: "Operations") }

    before { EntityDomainMembership.create!(customer: customer, entity_domain: domain, entity: entity) }

    it "lists unbound forms on the ungrouped domain's Forms tab, including a format-suffixed route" do
      orphan = create(:page, customer: customer, entity: entity, name: "Unbound audit form")
      orphan.entity_id = nil
      orphan.save!(validate: false)

      get "/#{customer.id}/admin/domains/ungrouped/pages.html"

      expect(response).to have_http_status(:ok)
      rows = Nokogiri::HTML(response.body).at_css("#pages-ops-table")
      expect(rows.text).to include(orphan.name)
      expect(rows.text).not_to include(valid_page.name)

      get "/#{customer.id}/admin/domains/#{domain.id}/pages"

      rows = Nokogiri::HTML(response.body).at_css("#pages-ops-table")
      expect(rows.text).to include(valid_page.name)
      expect(rows.text).not_to include(orphan.name)
    end

    it "lists stale override, bridge-bound and headless forms in the same unbound bucket as the counts" do
      shared_page = Current.set(customer: nil, shared_resources_mode: true) do
        create(:page, :shared, name: "Stale override form")
      end
      Current.set(customer: customer, shared_resources_mode: false) do
        loaded = Page.find(shared_page.id)
        loaded.entity_id = 999_999_999
        loaded.save!(validate: false)
      end
      bridge = create(:entity, customer: customer, category: :bridge)
      bridge_page = create(:page, customer: customer, entity: bridge, name: "Bridge-bound form")
      headless = create(:page, customer: customer, entity: entity, name: "Headless form")
      headless.update_column(:current_version_id, nil)

      get "/#{customer.id}/admin/domains/ungrouped/pages"

      expect(response).to have_http_status(:ok)
      table = Nokogiri::HTML(response.body).at_css("#pages-ops-table")
      expect(table.text).to include(shared_page.name, bridge_page.name, headless.name)
      expect(table.text).not_to include(valid_page.name)
      expect(Admin::Pages::BindingCounts.call(customer_id: customer.id)[nil].total).to eq(table.css("tbody tr").size)
    end
  end

  it "uses the same tenant override binding for the HTTP entity Forms tab and the counts" do
    global_entity, overridden_entity, shared_page = Current.set(customer: nil, shared_resources_mode: true) do
      first = create(:entity, :shared)
      second = create(:entity, :shared)
      [first, second, create(:page, :shared, entity: first, name: "Effective override form")]
    end
    global_head = shared_page.current_version_id
    Current.set(customer: customer, shared_resources_mode: false) do
      loaded = Page.find(shared_page.id)
      loaded.entity_id = overridden_entity.id
      loaded.save!
    end

    get "/#{customer.id}/admin/entities/#{global_entity.id}/pages"
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("#pages-ops-table").text).not_to include(shared_page.name)

    get "/#{customer.id}/admin/entities/#{overridden_entity.id}/pages"
    expect(response).to have_http_status(:ok)
    table = Nokogiri::HTML(response.body).at_css("#pages-ops-table")
    expect(table.text).to include(shared_page.name)
    counts = Admin::Pages::BindingCounts.call(customer_id: customer.id)
    expect(counts[global_entity.id].total).to eq(0)
    expect(counts[overridden_entity.id].total).to eq(table.css("tbody tr").size)

    other = create(:customer)
    sign_in create(:user, :admin, customer: other)
    get "/#{other.id}/admin/entities/#{global_entity.id}/pages"
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("#pages-ops-table").text).to include(shared_page.name)
    expect(shared_page.reload.current_version_id).to eq(global_head)
  end
end
