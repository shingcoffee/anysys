# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Constants index", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/maintenance/constants" }

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :post

  describe "GET new — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/constants/new" }

    it_behaves_like "an admin-guarded GET"
  end

  let!(:c1) { create(:constant, name: "Color", customer: customer) }

  describe "GET show — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/constants/#{c1.id}" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET edit — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/constants/#{c1.id}/edit" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "PATCH update — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/constants/#{c1.id}" }

    it_behaves_like "an admin-guarded request", :patch
  end

  describe "DELETE destroy — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/constants/#{c1.id}" }

    it_behaves_like "an admin-guarded request", :delete
  end

  it "renders the new AdminTableComponent table with richer columns" do
    get "/#{customer.id}/admin/maintenance/constants"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-controller="admin-table"')
    %w[Name Options Updated].each do |label|
      expect(response.body).to include(label)
    end
  end

  it "GET show localizes created_at instead of ISO strftime" do
    get "/#{customer.id}/admin/maintenance/constants/#{c1.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.l(c1.created_at, format: :long))
    expect(response.body).not_to include(c1.created_at.strftime("%Y-%m-%d %H:%M:%S"))
  end

  describe "JSON (the 'Use Constant' attribute picker source)" do
    let!(:own)         { create(:constant, :customer_specific, customer: customer, name: "OwnColor") }
    let!(:shared)      { create(:constant, :shared, name: "Countries", options: %w[US CA]) }
    let!(:other_owned) { create(:constant, :customer_specific, customer: create(:customer), name: "Foreign") }

    it "returns this customer's own constants and every shared one" do
      get "/#{customer.id}/admin/maintenance/constants.json"

      expect(response).to have_http_status(:ok)
      payload = JSON.parse(response.body)
      names   = payload.map { |c| c["name"] }

      expect(names).to include("OwnColor", "Countries")     # own + shared
      expect(names).not_to include("Foreign")            # another tenant's constant
      shared_row = payload.find { |c| c["name"] == "Countries" }
      expect(shared_row["options"]).to eq(%w[US CA])     # picker needs the options
    end

    it "is not paginated, so shared constants stay reachable past the page size" do
      create_list(:constant, Listable::DEFAULT_PER_PAGE + 5, :customer_specific, customer: customer)

      get "/#{customer.id}/admin/maintenance/constants.json"

      names = JSON.parse(response.body).map { |c| c["name"] }
      expect(names).to include("Countries")
      expect(names.size).to be > Listable::DEFAULT_PER_PAGE
    end
  end
end

# ---------------------------------------------------------------------------
# Platform-owner full CRUD on shared constants
# ---------------------------------------------------------------------------
RSpec.describe "Admin::Maintenance::Constants — platform owner shared-constant CRUD", type: :request do
  include_context "as platform owner"

  let!(:shared_constant) { create(:constant, :shared, name: "Global Status", options: %w[Active Inactive]) }
  let(:platform_cid) { customer.id }

  # 1. Platform owner can UPDATE a shared constant (change name + options) -----------
  describe "PATCH/PUT shared constant as platform owner" do
    it "writes a per-customer override from tenant maintenance and ignores name" do
      patch "/#{platform_cid}/admin/maintenance/constants/#{shared_constant.id}",
            params: { constant: { name: "Updated Global Status", options: '["Yes","No","Maybe"]' } }

      expect(response).to have_http_status(:redirect)
      shared_constant.reload
      expect(shared_constant.name).to eq("Global Status")
      Current.with_customer(nil) { expect(Constant.find(shared_constant.id).options).to eq(%w[Active Inactive]) }
      Current.with_customer(customer) { expect(Constant.find(shared_constant.id).options).to eq(%w[Yes No Maybe]) }
      ov = ConstantCustomerOverride.find_by(constant_id: shared_constant.id, customer_id: platform_cid)
      expect(ov.options).to eq(%w[Yes No Maybe])
    end

    it "advances the shared constant from Shared Resources" do
      patch "/#{platform_cid}/admin/maintenance/platform/constants/#{shared_constant.id}",
            params: { constant: { name: "Updated Global Status", options: '["Yes","No","Maybe"]' } }

      expect(response).to have_http_status(:redirect)
      shared_constant.reload
      expect(shared_constant.name).to eq("Updated Global Status")
      expect(shared_constant.options).to eq(%w[Yes No Maybe])
      expect(ConstantCustomerOverride.where(constant_id: shared_constant.id)).to be_empty
    end
  end

  # 1b. Every update refreshes the "last updated" time, even a no-op resubmit -------
  describe "PATCH shared constant with no attribute changes" do
    it "still bumps updated_at so the Save is reflected in the last-updated time" do
      shared_constant.update_column(:updated_at, 2.days.ago)
      before_ts = shared_constant.reload.updated_at

      patch "/#{platform_cid}/admin/maintenance/platform/constants/#{shared_constant.id}",
            params: { constant: { name: shared_constant.name,
                                  options: shared_constant.options.to_json } }

      expect(response).to have_http_status(:redirect)
      expect(shared_constant.reload.updated_at).to be > before_ts
    end
  end

  # 2. Platform owner can DELETE a shared constant -----------------------------------
  describe "DELETE shared constant as platform owner" do
    it "does not remove the record from the tenant path" do
      expect {
        delete "/#{platform_cid}/admin/maintenance/constants/#{shared_constant.id}"
      }.not_to change(Constant, :count)
      expect(response).to have_http_status(:redirect)
    end

    it "removes the record from Shared Resources" do
      expect {
        delete "/#{platform_cid}/admin/maintenance/platform/constants/#{shared_constant.id}"
      }.to change(Constant, :count).by(-1)
      expect(response).to have_http_status(:redirect)
    end
  end

  # 3. Platform owner GETs the edit page for a shared constant -----------------------
  describe "GET edit page for a shared constant as platform owner" do
    it "renders 200 with an editable name field and no type/sharing-scope field" do
      get "/#{platform_cid}/admin/maintenance/constants/#{shared_constant.id}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="constant[name]"')
      expect(response.body).not_to include("constant_type")
      expect(response.body).not_to include("Sharing Scope")
    end
  end

  # 4. Show page exposes Edit + Delete and NOT the read-only alert --------------------
  describe "GET show page for a shared constant as platform owner" do
    it "renders Edit on the tenant path and no delete of the shared row" do
      get "/#{platform_cid}/admin/maintenance/constants/#{shared_constant.id}"
      expect(response).to have_http_status(:ok)

      edit_path = edit_admin_maintenance_constant_path(platform_cid, shared_constant)
      expect(response.body).to include(edit_path)
      expect(response.body).not_to include('data-turbo-method="delete"')
      expect(response.body).not_to include("cannot be edited")
    end

    it "renders Edit and Delete on Shared Resources" do
      get "/#{platform_cid}/admin/maintenance/platform/constants/#{shared_constant.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-turbo-method="delete"')
    end
  end
end

# ---------------------------------------------------------------------------
# Regular tenant admin — blocked from mutating shared constants
# ---------------------------------------------------------------------------
RSpec.describe "Admin::Maintenance::Constants — regular admin shared-constant guards", type: :request do
  include_context "as admin"

  let!(:shared_constant) { create(:constant, :shared, name: "Platform Colors", options: %w[Red Blue]) }

  # 5a. HTML: regular admin attempting UPDATE a shared constant ----------------------
  describe "PATCH shared constant as regular tenant admin (HTML)" do
    it "writes a per-customer override and leaves the global name/options unchanged" do
      patch "/#{customer.id}/admin/maintenance/constants/#{shared_constant.id}",
            params: { constant: { name: "Hacked Name", options: '["X"]' } }

      expect(response).to have_http_status(:redirect)

      shared_constant.reload
      expect(shared_constant.name).to eq("Platform Colors")
      Current.with_customer(nil) { expect(Constant.find(shared_constant.id).options).to eq(%w[Red Blue]) }
      ov = ConstantCustomerOverride.find_by(constant_id: shared_constant.id, customer_id: customer.id)
      expect(ov.options).to eq(%w[X])
    end

    it "does not pin an override when the submitted options already match the global default" do
      expect {
        patch "/#{customer.id}/admin/maintenance/constants/#{shared_constant.id}",
              params: { constant: { name: "Hacked Name", options: '["Red","Blue"]' } }
      }.not_to change(ConstantCustomerOverride, :count)

      expect(response).to have_http_status(:redirect)
      shared_constant.reload
      expect(shared_constant.name).to eq("Platform Colors")
      Current.with_customer(nil) { expect(Constant.find(shared_constant.id).options).to eq(%w[Red Blue]) }
      expect(ConstantCustomerOverride.find_by(constant_id: shared_constant.id, customer_id: customer.id)).to be_nil
    end
  end

  describe "PATCH shared constant as regular tenant admin (JSON)" do
    it "writes a per-customer override" do
      patch "/#{customer.id}/admin/maintenance/constants/#{shared_constant.id}.json",
            params: { constant: { name: "Hacked Name", options: '["X"]' } }

      expect(response).to have_http_status(:ok)
      expect(shared_constant.reload.name).to eq("Platform Colors")
      ov = ConstantCustomerOverride.find_by(constant_id: shared_constant.id, customer_id: customer.id)
      expect(ov.options).to eq(%w[X])
    end
  end

  # 6. Regular admin attempting DELETE a shared constant is blocked ------------------
  describe "DELETE shared constant as regular tenant admin" do
    it "does not remove the record" do
      expect {
        delete "/#{customer.id}/admin/maintenance/constants/#{shared_constant.id}"
      }.not_to change(Constant, :count)

      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(response.body).to include(I18n.t("maint_core.flash.shared_resources.platform_path_only"))
    end
  end

  # 7. Regular admin show page for a shared constant — override, not copy-to-customer
  describe "GET show page for a shared constant as regular tenant admin" do
    it "shows Edit and the override notice, not Copy to Customer or Delete" do
      get "/#{customer.id}/admin/maintenance/constants/#{shared_constant.id}"
      expect(response).to have_http_status(:ok)

      expect(response.body).to include(I18n.t("maint_core.constants.show.shared_override_notice"))
      copy_path = admin_maintenance_constant_copy_path(customer.id, shared_constant)
      expect(response.body).not_to include(copy_path)
      edit_path = edit_admin_maintenance_constant_path(customer.id, shared_constant)
      expect(response.body).to include(edit_path)
      expect(response.body).not_to include('data-turbo-method="delete"')
    end
  end
end

# ---------------------------------------------------------------------------
# ConstantCopiesController — customer-owned copy stays; shared copy-to-customer is gone
# ---------------------------------------------------------------------------
RSpec.describe "Admin::Maintenance::ConstantCopies", type: :request do
  include_context "as admin"

  let!(:local_constant) { create(:constant, :customer_specific, customer: customer, name: "Local Regions", options: %w[NA]) }
  let(:guard_path) { "/#{customer.id}/admin/maintenance/constants/#{local_constant.id}/copy" }

  it_behaves_like "an admin-guarded GET"

  describe "GET copy path for a customer-owned constant" do
    it "returns 200 and pre-fills the name with 'Copy of <original name>'" do
      get "/#{customer.id}/admin/maintenance/constants/#{local_constant.id}/copy"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Copy of Local Regions")
    end
  end

  describe "GET copy path for a shared constant" do
    let!(:shared_constant) { create(:constant, :shared, name: "Global Regions", options: %w[NA EU APAC]) }

    it "returns 404 — tenant overrides replace copy-to-customer" do
      get "/#{customer.id}/admin/maintenance/constants/#{shared_constant.id}/copy"
      expect(response).to have_http_status(:not_found)
    end
  end

  # 3 (follow-up). Cross-tenant copy guard — another tenant's customer-specific
  # constant is outside Constant.accessible and must 404, not leak data.
  describe "GET copy path for another tenant's customer-specific constant" do
    let(:other_customer)          { create(:customer) }
    let!(:foreign_constant) do
      create(:constant, :customer_specific, customer: other_customer, name: "Foreign Constant")
    end

    it "returns 404 (not found) — other tenant's record is outside accessible scope" do
      get admin_maintenance_constant_copy_path(customer.id, foreign_constant)
      expect(response).to have_http_status(:not_found)
    end
  end
end

# ---------------------------------------------------------------------------
# Shared identity is customer_id (cannot reassign on update)
# ---------------------------------------------------------------------------
RSpec.describe "Admin::Maintenance::Constants — shared identity stays platform-owned on update", type: :request do
  include_context "as platform owner"

  let(:platform_cid) { customer.id }

  describe "PATCH shared constant keeps customer_id nil" do
    let!(:shared_constant) do
      create(:constant, :shared, name: "Immutable Shared", options: %w[A B])
    end

    it "succeeds (302), keeps the constant shared, and records an override without renaming" do
      patch "/#{platform_cid}/admin/maintenance/constants/#{shared_constant.id}",
            params: { constant: { name: "Immutable Shared Updated",
                                  options: '["A","B","C"]' } }

      expect(response).to have_http_status(:redirect)

      shared_constant.reload
      expect(shared_constant.name).to eq("Immutable Shared")
      Current.with_customer(nil) { expect(Constant.find(shared_constant.id).options).to eq(%w[A B]) }
      expect(shared_constant.shared?).to be true
      expect(shared_constant.customer_id).to be_nil
      ov = ConstantCustomerOverride.find_by(constant_id: shared_constant.id, customer_id: platform_cid)
      expect(ov.options).to eq(%w[A B C])
    end
  end
end

# ---------------------------------------------------------------------------
# Tenant create cannot publish a Shared Resource
# ---------------------------------------------------------------------------
RSpec.describe "Admin::Maintenance::Constants — tenant create cannot publish a Shared Resource", type: :request do
  include_context "as admin"

  describe "POST create on the tenant constants path" do
    it "creates a customer-owned constant assigned to the admin's customer" do
      expect {
        post "/#{customer.id}/admin/maintenance/constants",
             params: { constant: { name: "Sneaky Shared",
                                   options: '["X","Y"]' } }
      }.to change(Constant, :count).by(1)

      expect(response).to have_http_status(:redirect)

      created = Constant.order(:created_at).last
      expect(created.customer_owned?).to be true
      expect(created.customer_id).to eq(customer.id)
    end
  end
end

# ---------------------------------------------------------------------------
# Clickable constant name → detail page (row_path link in index)
# ---------------------------------------------------------------------------
RSpec.describe "Admin::Maintenance::Constants — index row_path link", type: :request do
  include_context "as admin"

  let!(:c1) { create(:constant, :customer_specific, customer: customer, name: "ClickableConstant") }

  # 4 (follow-up). The index wires row_path into AdminTableComponent, which wraps
  # the first column cell in an <a href="...">. Assert the show path appears in the
  # rendered HTML as an href attribute.
  describe "GET constants index" do
    it "renders an anchor whose href points to the constant's show path" do
      get "/#{customer.id}/admin/maintenance/constants"

      expect(response).to have_http_status(:ok)

      show_path = admin_maintenance_constant_path(customer.id, c1)
      expect(response.body).to include(show_path)
      # Verify it is rendered as an href (i.e. an actual link, not just a stray string)
      expect(response.body).to include(%(href="#{show_path}"))
    end
  end
end

# ---------------------------------------------------------------------------
# JSON format branches — show, create, update, destroy
# These cover the format.json respond_to blocks that HTML-only tests miss.
# ---------------------------------------------------------------------------
RSpec.describe "Admin::Maintenance::Constants — JSON format branches", type: :request do
  include_context "as admin"

  let!(:constant) { create(:constant, :customer_specific, customer: customer, name: "JsonConst", options: %w[A B]) }

  # show.json
  describe "GET show.json" do
    it "returns the constant as JSON" do
      get "/#{customer.id}/admin/maintenance/constants/#{constant.id}.json"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["id"]).to eq(constant.id)
      expect(body["name"]).to eq("JsonConst")
    end
  end

  # create.json — success
  describe "POST create.json — valid params" do
    it "creates the constant and returns 201" do
      expect {
        post "/#{customer.id}/admin/maintenance/constants.json",
             params: { constant: { name: "NewConst", options: %w[X Y] } }
      }.to change(Constant, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["name"]).to eq("NewConst")
    end
  end

  # create.json — failure (duplicate name within same tenant)
  describe "POST create.json — invalid params" do
    it "returns 422 with errors" do
      post "/#{customer.id}/admin/maintenance/constants.json",
           params: { constant: { name: "" } }  # blank name fails validation

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to have_key("errors")
    end
  end

  # update.json — success
  describe "PATCH update.json — valid params" do
    it "updates and returns the constant" do
      patch "/#{customer.id}/admin/maintenance/constants/#{constant.id}.json",
            params: { constant: { name: "UpdatedConst" } }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq("UpdatedConst")
    end
  end

  # update.json — failure
  describe "PATCH update.json — invalid params" do
    it "returns 422 with errors" do
      patch "/#{customer.id}/admin/maintenance/constants/#{constant.id}.json",
            params: { constant: { name: "" } }  # blank name is invalid

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to have_key("errors")
    end
  end

  # destroy.json
  describe "DELETE destroy.json — customer-specific constant" do
    it "returns 204 no content" do
      expect {
        delete "/#{customer.id}/admin/maintenance/constants/#{constant.id}.json"
      }.to change(Constant, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  # new action — HTML
  describe "GET new" do
    it "returns 200 with the form" do
      get "/#{customer.id}/admin/maintenance/constants/new"
      expect(response).to have_http_status(:ok)
    end
  end

  # create HTML failure — renders :new with 422
  describe "POST create — invalid params (HTML)" do
    it "re-renders the new form with 422" do
      post "/#{customer.id}/admin/maintenance/constants",
           params: { constant: { name: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # options submitted as a JSON string (the form serializes to JSON before POST)
  describe "POST create — options submitted as JSON string" do
    it "creates the constant, parsing the JSON string into an array" do
      expect {
        post "/#{customer.id}/admin/maintenance/constants",
             params: { constant: { name: "JsonOptConst", options: '["Red","Blue"]' } }
      }.to change(Constant, :count).by(1)

      expect(response).to have_http_status(:redirect)
      c = Constant.order(:created_at).last
      expect(c.options).to include("Red", "Blue")
    end
  end

  describe "POST create — empty options array" do
    it "returns 422 and does not persist" do
      expect {
        post "/#{customer.id}/admin/maintenance/constants",
             params: { constant: { name: "EmptyOpts", options: "[]" } }
      }.not_to change(Constant, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST create — duplicate options" do
    it "returns 422 and does not persist" do
      expect {
        post "/#{customer.id}/admin/maintenance/constants",
             params: { constant: { name: "DupOpts", options: '["Option 1", "Option 2", "Option 1"]' } }
      }.not_to change(Constant, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # options submitted as an invalid JSON string → rescued, treated as empty array,
  # fails `presence: true` validation → 422
  describe "POST create — options submitted as unparseable JSON string" do
    it "treats invalid JSON options as empty array and re-renders new with 422" do
      post "/#{customer.id}/admin/maintenance/constants",
           params: { constant: { name: "BadJsonConst", options: "not valid json {{" } }

      # Empty options fails the presence validation
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end

# ---------------------------------------------------------------------------
# ensure_editable JSON branch for shared constant — platform owner vs regular admin
# (covers the format.json render in ensure_editable)
# ---------------------------------------------------------------------------
RSpec.describe "Admin::Maintenance::Constants — ensure_editable JSON branch", type: :request do
  include_context "as admin"

  let!(:shared_constant) { create(:constant, :shared, name: "SharedForJson", options: %w[P Q]) }

  describe "DELETE shared constant as regular admin (JSON)" do
    it "returns 403 forbidden" do
      delete "/#{customer.id}/admin/maintenance/constants/#{shared_constant.id}.json"

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("Shared Resources")
    end
  end
end
