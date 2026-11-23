# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Platform Shared Resources", type: :request do
  include_context "as platform owner"

  let(:cid) { customer.id }
  let(:base) { "/#{cid}/admin/maintenance/platform" }
  let(:guard_path) { "#{base}/constants" }

  describe "authorization" do
    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "POST constants — auth guards" do
    let(:guard_path) { "#{base}/constants" }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "GET entities — auth guards" do
    let(:guard_path) { "#{base}/entities" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "POST entities — auth guards" do
    let(:guard_path) { "#{base}/entities" }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "GET entities new — auth guards" do
    let(:guard_path) { "#{base}/entities/new" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET flowcharts — auth guards" do
    let(:guard_path) { "#{base}/flowcharts" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "POST flowcharts — auth guards" do
    let(:guard_path) { "#{base}/flowcharts" }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "GET pages — auth guards" do
    let(:guard_path) { "#{base}/pages" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "POST pages — auth guards" do
    let(:guard_path) { "#{base}/pages" }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "GET constants new — auth guards" do
    let(:guard_path) { "#{base}/constants/new" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET pages new — auth guards" do
    let(:guard_path) { "#{base}/pages/new" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET flowcharts new — auth guards" do
    let(:guard_path) { "#{base}/flowcharts/new" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "DELETE shared entity — auth guards" do
    let!(:shared) { create(:entity, :shared, name: "GuardDeleteEntity") }
    let(:guard_path) { "#{base}/entities/#{shared.id}" }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  describe "POST shared page launch — auth guards" do
    let!(:shared) { create(:page, :shared, name: "GuardLaunchPage", launched: false) }
    let(:guard_path) { "#{base}/pages/#{shared.id}/launch" }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "PATCH shared page visibility — auth guards" do
    let!(:shared) { create(:page, :shared, name: "GuardVisPage") }
    let(:guard_path) { "#{base}/pages/#{shared.id}/visibility" }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "POST shared flowchart launch — auth guards" do
    let!(:shared) { create(:flowchart, :shared_type, :simple, :draft, name: "GuardLaunchFlow") }
    let(:guard_path) { "#{base}/flowcharts/#{shared.id}/launch" }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "DELETE shared constant — auth guards" do
    let!(:shared) { create(:constant, :shared, name: "GuardDeleteConst", options: %w[A]) }
    let(:guard_path) { "#{base}/constants/#{shared.id}" }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  describe "Constants" do
    it "creates a shared constant with no customer_id" do
      expect {
        post "#{base}/constants",
             params: { constant: { name: "SharedColors", options: '["Red","Blue"]' } }
      }.to change(Constant, :count).by(1)

      created = Constant.find_by(name: "SharedColors")
      expect(created).to be_shared
      expect(created.customer_id).to be_nil
    end

    it "lists only shared constants" do
      create(:constant, :shared, name: "PlatformConst")
      create(:constant, :customer_specific, customer: customer, name: "TenantConst")

      get "#{base}/constants"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("PlatformConst")
      expect(response.body).not_to include("TenantConst")
    end

    it "404s when a tenant-owned constant is requested" do
      local = create(:constant, :customer_specific, customer: customer, name: "LocalOnly")
      get "#{base}/constants/#{local.id}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "Entities" do
    it "creates a shared entity with no customer_id" do
      expect {
        post "#{base}/entities", params: { entity: { name: "SharedWidget" } }
      }.to change(Entity.unscoped, :count).by(1)

      created = Entity.unscoped.find_by(name: "SharedWidget")
      expect(created).to be_shared
      expect(created.customer_id).to be_nil
    end
  end

  describe "Flowcharts" do
    it "creates a shared flowchart with no customer_id" do
      expect {
        post "#{base}/flowcharts", params: { flowchart: { name: "SharedFlow" } }
      }.to change(Flowchart.unscoped, :count).by(1)

      created = Flowchart.unscoped.find_by(name: "SharedFlow")
      expect(created).to be_shared
      expect(created.customer_id).to be_nil
    end
  end

  describe "Pages" do
    let!(:shared_entity) { create(:entity, :shared, name: "SharedPageEntity") }

    it "creates a shared page with no customer_id" do
      expect {
        post "#{base}/pages",
             params: { page: { name: "Shared Landing", entity_id: shared_entity.id.to_s } }
      }.to change(Page.unscoped, :count).by(1)

      created = Page.unscoped.find_by(name: "Shared Landing")
      expect(created).to be_shared
      expect(created.customer_id).to be_nil
    end

    it "renders a launched public shared page for another tenant" do
      page_rec = create(:page, :shared, :for_member, :for_public, name: "Live Shared", launched: true)
      other = create(:customer)

      get "/#{other.id}/page/#{page_rec.public_uuid}"
      expect(response).to have_http_status(:ok)
    end

    it "renders a launched member-visible shared page for another tenant's member" do
      page_rec = create(:page, :shared, :for_member, name: "Member Shared", launched: true)
      other = create(:customer)
      sign_in create(:user, :member, customer: other)

      get "/#{other.id}/member/pages/#{page_rec.id}"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "tenant create cannot publish shared" do
    it "forces a tenant constant create to customer_specific" do
      post "/#{cid}/admin/maintenance/constants",
           params: { constant: { name: "Sneaky", options: '["A"]' } }
      created = Constant.find_by(name: "Sneaky")
      expect(created).to be_customer_owned
      expect(created.customer_id).to eq(cid)
    end
  end

  describe "tenant copy of a shared constant" do
    it "does not fork a local customer-specific copy" do
      shared = create(:constant, :shared, name: "ForkMe", options: %w[A B])
      get "/#{cid}/admin/maintenance/constants/#{shared.id}/copy"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "platform copy of a shared constant" do
    it "renders a new shared copy form" do
      shared = create(:constant, :shared, name: "DupMe", options: %w[A B])
      get "#{base}/constants/#{shared.id}/copy"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Copy of DupMe")
    end
  end

  describe "tenant list actions for shared records" do
    let(:tenant) { create(:customer) }
    let(:tenant_admin) { create(:user, :admin, customer: tenant) }

    describe "as a regular admin" do
      before { sign_in tenant_admin }

      it "keeps override edit and hides destroy for a shared entity" do
        shared = create(:entity, :shared, name: "SharedListedEntity")
        get "/#{tenant.id}/admin/maintenance/entities"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("SharedListedEntity")
        expect(response.body).to include("/#{tenant.id}/admin/maintenance/entities/#{shared.id}/edit")
        expect(response.body).not_to include("/#{tenant.id}/admin/maintenance/entities/#{shared.id}/copy")
        expect(response.body).not_to include(
          I18n.t("maint_core.entities.index.delete_confirm", name: shared.display_label)
        )
      end

      it "denies a regular admin the shared flowchart list" do
        shared = create(:flowchart, :shared_type, name: "SharedListedFlow")
        shared.update_columns(customer_id: nil)
        get "/#{tenant.id}/admin/maintenance/flowcharts"

        expect(response.status).not_to eq(200)
      end

      it "keeps override edit and hides destroy for a shared page" do
        shared = create(:page, :shared, name: "SharedListedPage")
        get "/#{tenant.id}/admin/maintenance/pages"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("SharedListedPage")
        expect(response.body).not_to include("/#{tenant.id}/admin/maintenance/pages/#{shared.id}/copy")
        expect(response.body).to include("/#{tenant.id}/admin/maintenance/pages/#{shared.id}/edit")
        expect(response.body).not_to include(
          I18n.t("maint_core.pages.index.delete_confirm", name: shared.name)
        )
      end

      it "writes a tenant override on HTML PATCH of a shared page and ignores name" do
        shared = create(:page, :shared, name: "ImmutableSharedPage")
        config = JSON.parse(shared.configuration)
        config["pages"] ||= [{ "id" => "page_1", "name" => "Page 1", "order" => 1, "fields" => [] }]
        config["pages"][0]["name"] = "Tenant Page Title"
        patch "/#{tenant.id}/admin/maintenance/pages/#{shared.id}",
              params: { page: { name: "Hacked", configuration: config.to_json, updated_at: shared.updated_at.iso8601(6) } }

        expect(response).to have_http_status(:redirect)
        expect(shared.reload.name).to eq("ImmutableSharedPage")
        expect(PageCustomerHead.find_by(page_id: shared.id, customer_id: tenant.id)).to be_present
      end

      it "writes a tenant override on JSON PATCH of a shared page and ignores name" do
        shared = create(:page, :shared, name: "ImmutableJsonPage")
        patch "/#{tenant.id}/admin/maintenance/pages/#{shared.id}",
              params: { page: { name: "Hacked", updated_at: shared.updated_at.iso8601(6) } },
              as: :json

        expect(response).to have_http_status(:ok)
        expect(shared.reload.name).to eq("ImmutableJsonPage")
      end
    end

    describe "as platform owner on a tenant list" do
      it "keeps tenant edit path for a shared entity and hides destroy" do
        create(:entity_domain, customer: customer)
        shared = create(:entity, :shared, name: "OwnerSeesSharedEntity")
        get "/#{cid}/admin/maintenance/entities", params: { domain_id: "ungrouped" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("/#{cid}/admin/maintenance/entities/#{shared.id}/edit")
        expect(response.body).not_to include("/#{cid}/admin/maintenance/platform/entities/#{shared.id}/edit")
        expect(response.body).not_to include(
          I18n.t("maint_core.entities.index.delete_confirm", name: shared.display_label)
        )
      end

      it "keeps tenant edit path for a shared flowchart and hides destroy" do
        shared = create(:flowchart, :shared_type, name: "OwnerSeesSharedFlow")
        shared.update_columns(customer_id: nil)
        get "/#{cid}/admin/maintenance/flowcharts"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("/#{cid}/admin/maintenance/flowcharts/#{shared.id}/edit")
        expect(response.body).not_to include("/#{cid}/admin/maintenance/platform/flowcharts/#{shared.id}/edit")
        expect(response.body).not_to include(
          I18n.t("maint_core.flowcharts.index.delete_confirm", name: shared.name)
        )
      end

      it "keeps tenant edit path for a shared page and hides destroy" do
        shared = create(:page, :shared, name: "OwnerSeesSharedPage")
        get "/#{cid}/admin/maintenance/pages"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("/#{cid}/admin/maintenance/pages/#{shared.id}/edit")
        expect(response.body).not_to include("/#{cid}/admin/maintenance/platform/pages/#{shared.id}/edit")
        expect(response.body).not_to include(
          I18n.t("maint_core.pages.index.delete_confirm", name: shared.name)
        )
      end

      it "rewrites index actions to platform paths and includes destroy" do
        shared = create(:entity, :shared, name: "PlatformDeleteableEntity")
        get "#{base}/entities"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("/#{cid}/admin/maintenance/platform/entities/#{shared.id}/edit")
        expect(response.body).to include("/#{cid}/admin/maintenance/platform/entities/new")
        expect(response.body).to include('data-turbo-method="delete"')
        expect(response.body).not_to include("/#{cid}/admin/maintenance/entities/#{shared.id}/edit")
      end
    end
  end

  describe "path-locked global CUD" do
    it "rejects owner DELETE of a shared entity on the tenant path" do
      shared = create(:entity, :shared, name: "OwnerTenantDeleteEntity")
      delete "/#{cid}/admin/maintenance/entities/#{shared.id}"
      expect(Entity.unscoped.exists?(shared.id)).to be(true)
      expect(response).to have_http_status(:redirect)
    end

    it "soft-deletes a shared entity from Shared Resources and cascades override heads" do
      shared = create(:entity, :shared, name: "PlatformDeleteEntity")
      other = create(:customer)
      Current.with_customer(other) do
        shared.description = "tenant override"
        shared.save!
      end
      expect(EntityCustomerHead.find_by(entity_id: shared.id, customer_id: other.id)).to be_present

      delete "#{base}/entities/#{shared.id}"
      expect(Entity.exists?(shared.id)).to be(false)
      expect(Entity.only_deleted.exists?(shared.id)).to be(true)
    end

    it "rejects owner DELETE of a shared constant on the tenant path and allows it on the platform path" do
      shared = create(:constant, :shared, name: "OwnerPathLockedConst", options: %w[A])
      expect {
        delete "/#{cid}/admin/maintenance/constants/#{shared.id}"
      }.not_to change(Constant, :count)

      expect {
        delete "#{base}/constants/#{shared.id}"
      }.to change(Constant, :count).by(-1)
    end

    it "rejects tenant-path launch of a shared page for the owner" do
      shared = create(:page, :shared, name: "SharedLaunchLock", launched: false)
      allow_any_instance_of(Page).to receive(:launch_errors).and_return([])
      post "/#{cid}/admin/maintenance/pages/#{shared.id}/launch"
      expect(shared.reload.launched).to be(false)
    end

    it "launches a shared page from Shared Resources" do
      shared = create(:page, :shared, name: "SharedLaunchOk", launched: false)
      allow_any_instance_of(Page).to receive(:launch_errors).and_return([])
      post "#{base}/pages/#{shared.id}/launch"
      expect(shared.reload.launched).to be(true)
    end

    it "rejects tenant-path visibility update of a shared page" do
      shared = create(:page, :shared, name: "SharedVisLock")
      patch "/#{cid}/admin/maintenance/pages/#{shared.id}/visibility",
            params: { page: { visible_audiences: %w[admin member public] } }
      expect(shared.reload.visible_audiences).to eq(%w[admin])
    end

    it "updates visibility of a shared page from Shared Resources" do
      shared = create(:page, :shared, name: "SharedVisOk")
      patch "#{base}/pages/#{shared.id}/visibility",
            params: { page: { visible_audiences: %w[admin member public] } }
      expect(shared.reload.visible_audiences).to eq(%w[admin member public])
    end

    it "rejects tenant-path launch of a shared flowchart" do
      shared = create(:flowchart, :shared_type, :simple, :draft, name: "SharedFlowLaunchLock")
      allow_any_instance_of(FlowchartInputOutputValidator::Result).to receive(:errors).and_return([])
      post "/#{cid}/admin/maintenance/flowcharts/#{shared.id}/launch"
      expect(shared.reload.status).to eq("draft")
    end

    it "launches a shared flowchart from Shared Resources" do
      shared = create(:flowchart, :shared_type, :simple, :draft, name: "SharedFlowLaunchOk")
      allow_any_instance_of(FlowchartInputOutputValidator::Result).to receive(:errors).and_return([])
      post "#{base}/flowcharts/#{shared.id}/launch"
      expect(shared.reload.status).to eq("launched")
    end
  end

  describe "shared create layout (tenant URL vs platform URL)" do
    shared_examples "the same AdminPage create chrome" do |resource, heading|
      it "renders #{heading} through AdminPageComponent on both prefixes" do
        get "/#{cid}/admin/maintenance/#{resource}/new"
        expect(response).to have_http_status(:ok)
        tenant = response.body
        expect(tenant).to include(">#{heading}<")
        expect(tenant).to include("text-subtitle")

        get "#{base}/#{resource}/new"
        expect(response).to have_http_status(:ok)
        platform = response.body
        expect(platform).to include(">#{heading}<")
        expect(platform).to include("text-subtitle")
      end
    end

    include_examples "the same AdminPage create chrome", "constants", "New Constant"
    include_examples "the same AdminPage create chrome", "entities", "Create Entity"
    include_examples "the same AdminPage create chrome", "flowcharts", "Create Flowchart"
    include_examples "the same AdminPage create chrome", "pages", "Create Page"

    it "keeps the entity form on one card — extend-base-model is a field, not a side column" do
      get "/#{cid}/admin/maintenance/entities/new"
      expect(response.body).not_to include("lg:col-span-2")
      expect(response.body).to include('id="entity_base_model_section"')

      get "#{base}/entities/new"
      expect(response.body).not_to include("lg:col-span-2")
      expect(response.body).to include('id="entity_base_model_section"')
      expect(response.body).to include("Extend Base Model")
      expect(response.body).not_to include("The base model this platform entity extends.")
    end
  end

  describe "POST entity version page" do
    let(:entity) { create(:entity, :shared, :with_name_status_schema, name: "SharedStudent") }

    it "creates a shared page from the version" do
      post "#{base}/entities/#{entity.id}/versions/#{entity.current_version.id}/page", as: :json
      expect(response).to have_http_status(:ok)
      page = Page.find(JSON.parse(response.body)["page_id"])
      expect(page.customer_id).to be_nil
      expect(page.entity_version_id).to eq(entity.current_version.id)
      expect(JSON.parse(response.body)["url"]).to include("/admin/maintenance/platform/pages/")
      expect(JSON.parse(response.body)["url"]).not_to include("/edit")
    end
  end
end
