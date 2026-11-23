# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Core route audit: path identity and public visitors", type: :request do
  let(:tenant) { create(:customer) }
  let(:other) { create(:customer) }
  let(:owner) { find_or_create_platform_owner }

  describe "platform path identity" do
    before { sign_in owner }

    it "creates shared constants and entities on formatted collection paths" do
      post "/81721200/admin/maintenance/platform/constants.json",
           params: { constant: { name: "Formatted shared options", options: %w[A B] } }
      expect(response).to have_http_status(:created)
      expect(Constant.find(response.parsed_body.fetch("id")).customer_id).to be_nil

      post "/81721200/admin/maintenance/platform/entities.json",
           params: { entity: { name: "Formatted shared definition" } }
      expect(response).to have_http_status(:created)
      expect(Entity.find(response.parsed_body.fetch("id")).customer_id).to be_nil
    end

    it "uses shared-only scope and global payloads on formatted collection reads" do
      shared = create(:constant, :shared, name: "Global options", options: %w[Global])
      create(:constant, customer: owner.customer, name: "Private options", options: %w[Private])
      ConstantCustomerOverride.create!(constant: shared, customer_id: owner.customer_id, options: %w[Override])

      get "/81721200/admin/maintenance/platform/constants.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(hash_including("id" => shared.id, "options" => %w[Global]))
      expect(response.parsed_body.map { |row| row.fetch("name") }).not_to include("Private options")
    end

    it "rejects a wrong actual CID despite forged query and body identities" do
      path = "/#{tenant.id}/admin/maintenance/platform/constants.json"
      get path, params: { customer_id: "81721200" }
      expect(response).to have_http_status(:not_found)

      expect {
        post path, params: { customer_id: "81721200", constant: { name: "Wrong prefix", options: %w[A] } }
      }.not_to change(Constant, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "uses PATH_INFO rather than a mount prefix when enforcing the platform CID" do
      get "/#{tenant.id}/admin/maintenance/platform/module_settings.json",
          params: { customer_id: "81721200" }, env: { "SCRIPT_NAME" => "/anysys" }
      expect(response).to have_http_status(:not_found)
    end

    it "restores a nested target customer using the platform outer path identity" do
      target = create(:customer)
      target.soft_delete

      patch "/81721200/admin/maintenance/platform/customers/#{target.id}/restoration"

      expect(response).to redirect_to(admin_maintenance_platform_customers_path(81721200))
      expect(Customer.unscoped.find(target.id)).to be_active
    end

    it "retains owner cross-tenant administration outside the platform namespace" do
      get "/#{tenant.id}/admin/maintenance/customer_profile"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "public visitor identity and tenant-owned attribution" do
    let(:visitor) { create(:user, :member, customer: other) }
    let!(:page) { create(:page, :for_member, :for_public, customer: tenant, launched: true) }

    it "allows a signed-in foreign visitor without making them a tenant-owned user" do
      sign_in visitor
      attribution = nil
      allow_any_instance_of(PublicPagesController).to receive(:prepare_page_render).and_wrap_original do |method, *args, **kwargs|
        controller = method.receiver
        attribution = [controller.current_customer_id, controller.current_tenant_user, Current.platform_owner_context?]
        method.call(*args, **kwargs)
      end

      get "/#{tenant.id}/page/#{page.public_uuid}", env: { "SCRIPT_NAME" => "/anysys" }

      expect(response).to have_http_status(:ok)
      expect(attribution).to eq([tenant.id, nil, false])
    end

    it "retains same-tenant attribution on a public page" do
      member = create(:user, :member, customer: tenant)
      sign_in member
      attributed_user = nil
      allow_any_instance_of(PublicPagesController).to receive(:prepare_page_render).and_wrap_original do |method, *args, **kwargs|
        attributed_user = method.receiver.current_tenant_user
        method.call(*args, **kwargs)
      end

      get "/#{tenant.id}/page/#{page.public_uuid}"

      expect(response).to have_http_status(:ok)
      expect(attributed_user).to eq(member)
    end

    it "does not relax foreign admin or member route checks" do
      sign_in create(:user, :admin, customer: other)
      get "/#{tenant.id}/admin/domains.json"
      expect(response).to have_http_status(:forbidden)

      sign_in visitor
      get "/#{tenant.id}/member/pages/#{page.id}.json"
      expect(response).to have_http_status(:forbidden)
    end

    it "restricts the member-page preview exception to same-tenant admins and owners" do
      page.update!(visible_audiences: %w[admin member])
      sign_in create(:user, :admin, customer: tenant)
      get "/#{tenant.id}/member/pages/#{page.id}"
      expect(response).to have_http_status(:ok)

      sign_in owner
      get "/#{tenant.id}/member/pages/#{page.id}.json"
      expect(response).to have_http_status(:forbidden)
    end
  end
end
