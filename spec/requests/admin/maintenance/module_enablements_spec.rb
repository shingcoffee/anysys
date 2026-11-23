# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::ModuleEnablements", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  # A non-required feature module with a null registration class (NullRegistration).
  let!(:feature_module) { create(:feature_module, required: false) }

  def enablement_path(mod = feature_module) = "/#{customer.id}/admin/maintenance/modules/#{mod.id}/enablement"

  def assignment_for(mod)
    FeatureModules::CustomerAssignment.find_by(customer_id: customer.id, feature_module_id: mod.id)
  end

  describe "GET index — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/modules" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET index" do
    before { sign_in admin }

    it "lists available modules" do
      get "/#{customer.id}/admin/maintenance/modules"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(feature_module.name)
    end
  end

  describe "POST create — website provisioning result" do
    let!(:website_module) { find_or_create_feature_module!("website", name: "Website") }

    before { sign_in admin }

    it "enables the website module only after successful provisioning" do
      site = create(:website, customer: customer)
      result = Websites::Activities::Provision::Result.new(success?: true, model: site, errors: [])
      expect(Websites::Activities::Provision).to receive(:call).with(customer: customer).and_return(result)

      post enablement_path(website_module)

      expect(response).to redirect_to(admin_maintenance_modules_url(customer.id))
      expect(assignment_for(website_module).status).to eq("active")
      expect(flash[:notice]).to eq(I18n.t("maint_core.flash.module_enablements.enabled", name: website_module.display_name))
      expect(site.reload).not_to be_published
    end

    it "rolls back partial provisioning and creates no assignment for a failed result" do
      expect(Websites::Activities::Provision).to receive(:call).with(customer: customer) do
        site = create(:website, customer: customer)
        create(:website_page, :home, website: site)
        Websites::Activities::Provision::Result.new(success?: false, model: site, errors: ["secret provisioning details"])
      end

      expect {
        post enablement_path(website_module)
      }.not_to change(Website, :count)

      expect(response).to redirect_to(admin_maintenance_modules_url(customer.id))
      expect(assignment_for(website_module)).to be_nil
      expect(WebsitePage.where(customer_id: customer.id)).not_to exist
      expect(flash[:notice]).to be_nil
      expect(flash[:alert]).to eq(I18n.t("maint_core.flash.module_enablements.enable_failed"))
      expect(flash[:alert]).not_to include("secret provisioning details")
    end

    it "keeps a suspended assignment suspended when provisioning fails without a model or errors" do
      assignment = ensure_customer_feature_module(customer, website_module, status: :suspended)
      result = Websites::Activities::Provision::Result.new(success?: false, model: nil, errors: [])
      expect(Websites::Activities::Provision).to receive(:call).with(customer: customer).and_return(result)

      post enablement_path(website_module)

      expect(response).to redirect_to(admin_maintenance_modules_url(customer.id))
      expect(assignment.reload.status).to eq("suspended")
      expect(flash[:alert]).to eq(I18n.t("maint_core.flash.module_enablements.enable_failed"))
      expect(flash[:notice]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "POST create — auth guards" do
    let(:guard_path) { enablement_path }

    it_behaves_like "an admin-guarded request", :post
  end

  # ---------------------------------------------------------------------------
  # POST create — enable a module
  # ---------------------------------------------------------------------------

  describe "POST create — enable a module" do
    before { sign_in admin }

    it "creates a CustomerAssignment with status active and redirects to modules index" do
      expect {
        post enablement_path
      }.to change(FeatureModules::CustomerAssignment, :count).by(1)

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(admin_maintenance_modules_url(customer.id))
      expect(flash[:notice]).to match(/has been enabled/i)

      expect(assignment_for(feature_module).status).to eq("active")
    end

    it "interpolates #display_name into the enable notice, not the stored English name" do
      allow_any_instance_of(FeatureModules::Module).to receive(:display_name).and_return("Localized module")

      post enablement_path

      expect(flash[:notice]).to eq(I18n.t("maint_core.flash.module_enablements.enabled", name: "Localized module"))
    end

    it "is idempotent — re-enabling an already-active module does not raise" do
      create(:customer_feature_module, customer: customer, feature_module: feature_module)

      post enablement_path
      expect(response).to have_http_status(:redirect)
    end

    it "does not leak the exception message when provision fails" do
      allow(FeatureModules::Module::NullRegistration).to receive(:provision!)
        .and_raise(RuntimeError, "secret token abc")

      post enablement_path

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq(I18n.t("maint_core.flash.module_enablements.enable_failed"))
      expect(flash[:alert]).not_to include("secret token")
    end
  end

  # ---------------------------------------------------------------------------
  # POST create — inactive module guard (regression: fix #1)
  # ---------------------------------------------------------------------------

  describe "POST create — inactive module is rejected" do
    let!(:inactive_module) { create(:feature_module, :inactive) }

    before { sign_in admin }

    it "redirects with an alert and does NOT create a CustomerAssignment" do
      expect {
        post enablement_path(inactive_module)
      }.not_to change(FeatureModules::CustomerAssignment, :count)

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(admin_maintenance_modules_url(customer.id))
      expect(flash[:alert]).to match(/is not available/i)
    end

    it "leaves no active assignment behind for the inactive module" do
      post enablement_path(inactive_module)

      expect(assignment_for(inactive_module)).to be_nil
    end

    it "still enables an ACTIVE module (guard does not break the happy path)" do
      # feature_module is active (default factory trait)
      expect {
        post enablement_path
      }.to change(FeatureModules::CustomerAssignment, :count).by(1)

      expect(flash[:notice]).to match(/has been enabled/i)

      expect(assignment_for(feature_module).status).to eq("active")
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy — disable a module
  # ---------------------------------------------------------------------------

  describe "DELETE destroy — disable a module" do
    let!(:assignment) do
      create(:customer_feature_module, customer: customer, feature_module: feature_module)
    end

    before { sign_in admin }

    it "sets the assignment status to suspended and redirects" do
      delete enablement_path

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(admin_maintenance_modules_url(customer.id))
      expect(flash[:notice]).to match(/has been disabled/i)
      expect(assignment.reload.status).to eq("suspended")
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy — cannot disable a required module
  # ---------------------------------------------------------------------------

  describe "DELETE destroy — required module cannot be disabled" do
    # Touch customer first so that enable_required_feature_modules does NOT
    # auto-provision required_module (which is created afterward). The lazy
    # `customer` let would otherwise be first evaluated inside `let!(:required_assignment)`,
    # which would trigger the Customer after_create callback AFTER required_module
    # already exists, auto-provisioning it and causing a uniqueness conflict.
    let!(:customer_primed) { customer }
    let!(:required_module) { create(:feature_module, required: true) }
    let!(:required_assignment) do
      ensure_customer_feature_module(customer, required_module, status: :active, enabled_at: Time.current)
    end

    before { sign_in admin }

    it "redirects with an alert and leaves the assignment active" do
      delete enablement_path(required_module)

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to match(/required module/i)
      expect(required_assignment.reload.status).to eq("active")
    end
  end
end
