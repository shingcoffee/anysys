# spec/requests/admin/pages_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Pages", type: :request do
  let(:customer)  { create(:customer) }
  let(:admin)     { create(:user, :admin, customer: customer) }
  let!(:contact)  { create(:entity, customer: customer, name: "Contact") }
  let!(:donation) { create(:entity, customer: customer, name: "Donation") }
  let!(:c1)       { create(:page, customer: customer, entity: contact,  name: "Contact Form A") }
  let!(:d1)       { create(:page, customer: customer, entity: donation, name: "Donation Page") }

  describe "GET show — publishing panel" do
    let(:guard_path) { "/#{customer.id}/admin/pages/#{c1.id}" }

    it_behaves_like "an admin-guarded GET"

    it "renders the publishing slide-over in the page-publishing frame" do
      sign_in admin
      get "/#{customer.id}/admin/pages/#{c1.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('turbo-frame id="page-publishing"')
      expect(response.body).to include('data-controller="slide-over"')
      expect(response.body).to include(c1.name)
      expect(response.body).to include(I18n.t("comp_misc.distribution.header_title_html"))
      expect(response.body).to include(admin_maintenance_page_preview_path(customer.id, c1))
    end

    it "closes back to the Forms tab of the page's entity" do
      sign_in admin
      get "/#{customer.id}/admin/pages/#{c1.id}"
      close = Nokogiri::HTML(response.body).css("a[data-action='slide-over#close']").map { |link| link["href"] }
      expect(close).to eq(["/#{customer.id}/admin/entities/#{contact.id}/pages"])
    end
  end

  describe "cross-tenant isolation" do
    let(:other_page) { create(:page, customer: create(:customer)) }

    before { sign_in admin }

    it "returns 404 for another tenant's page show" do
      get "/#{customer.id}/admin/pages/#{other_page.id}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH batch — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/pages/batch" }

    it_behaves_like "an admin-guarded request", :patch
  end

  describe "PATCH /admin/pages/batch" do
    before { sign_in admin }

    let(:batch_path) { "/#{customer.id}/admin/pages/batch" }
    let(:pages_path) { "/#{customer.id}/admin/domains" }

    it "activates selected pages" do
      c1.update_column(:status, Page.statuses[:inactive])
      patch batch_path, params: { ids: [c1.id.to_s], action_key: "activate" }
      expect(response).to redirect_to(pages_path)
      expect(c1.reload.status).to eq("active")
    end

    it "deactivates selected pages" do
      patch batch_path, params: { ids: [c1.id.to_s], action_key: "deactivate" }
      expect(response).to redirect_to(pages_path)
      expect(c1.reload.status).to eq("inactive")
    end

    it "launches selected pages" do
      [c1, d1].each do |page|
        config = page.configuration_json
        config["pages"][0]["fields"] = [{ "id" => "name_field", "field_type" => "text", "label" => "Name" }]
        page.update!(configuration: config.to_json)
      end
      patch batch_path, params: { ids: [c1.id.to_s, d1.id.to_s], action_key: "launch" }
      expect(response).to redirect_to(pages_path)
      expect(c1.reload.launched).to be true
      expect(d1.reload.launched).to be true
    end

    it "takes pages offline" do
      c1.update_column(:launched, true)
      patch batch_path, params: { ids: [c1.id.to_s], action_key: "take_offline" }
      expect(response).to redirect_to(pages_path)
      expect(c1.reload.launched).to be false
    end

    it "redirects even when action_key is unrecognized" do
      patch batch_path, params: { ids: [c1.id.to_s], action_key: "unknown_action" }
      expect(response).to redirect_to(pages_path)
      expect(flash[:alert]).to eq(I18n.t("routes_audit.pages.invalid_action"))
      expect(flash[:notice]).to be_nil
    end

    it "scopes to own customer so other tenant pages are untouched" do
      other_customer = create(:customer)
      other_entity   = create(:entity, customer: other_customer)
      other_page     = create(:page, customer: other_customer, entity: other_entity, launched: false)

      patch batch_path, params: { ids: [other_page.id.to_s], action_key: "launch" }

      expect(other_page.reload.launched).to be false
    end

    it "includes the count in the notice" do
      patch batch_path, params: { ids: [c1.id.to_s, d1.id.to_s], action_key: "activate" }
      expect(flash[:notice]).to match(/2 pages updated/)
    end
  end

  describe "GET /form is gone" do
    it "does not serve the former fill-in surface" do
      sign_in admin
      get "/#{customer.id}/admin/pages/#{c1.id}/form"

      expect(response).to have_http_status(:not_found)
    end
  end
end
