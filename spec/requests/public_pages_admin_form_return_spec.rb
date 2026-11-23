# frozen_string_literal: true

require "rails_helper"

# An admin who submits a public page endpoint without the entity-entry return
# token lands on the form's catalog tab. The token is symbolic, so nobody can
# steer the redirect elsewhere.
RSpec.describe "Public page submission — admin catalog return", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }
  let!(:page_rec) do
    Current.set(customer: customer) do
      create(:page, customer: customer, entity: entity, launched: true,
                    configuration: {
                      metadata: { entity_id: entity.id, entity_name: entity.name },
                      fields: []
                    }.to_json)
    end
  end
  let(:url) { "/#{customer.id}/page/#{page_rec.public_uuid}" }
  let(:catalog_path) { admin_entity_pages_path(customer.id, entity) }

  context "as a same-tenant admin" do
    before { sign_in create(:user, :admin, customer: customer) }

    it "returns to the form's catalog tab" do
      post url
      expect(response).to redirect_to(catalog_path)
    end

    it "returns to the catalog tab for a public page instead of the public URL" do
      page_rec.update!(audience_member: true, audience_public: true)
      post url
      expect(response).to redirect_to(catalog_path)
    end

    it "ignores a leftover admin-form token" do
      post url, params: { return_to: "admin_form" }
      expect(response).to redirect_to(catalog_path)
    end

    it "ignores any other return_to value" do
      post url, params: { return_to: "https://evil.example/phish" }
      expect(response).to redirect_to(catalog_path)
    end
  end

  it "ignores the token for a member on a member page" do
    page_rec.update!(audience_member: true)
    sign_in create(:user, :member, customer: customer)

    post url, params: { return_to: "admin_form" }

    expect(response).to redirect_to(member_page_path(customer_id: customer.id, id: page_rec.id))
  end

  it "ignores the token for an anonymous visitor on a public page" do
    page_rec.update!(audience_member: true, audience_public: true)

    post url, params: { return_to: "admin_form" }

    expect(response.location).not_to include("/admin/")
  end
end
