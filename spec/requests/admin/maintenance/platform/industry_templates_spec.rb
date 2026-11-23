# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::IndustryTemplates", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let(:other_customer) { create(:customer, name: "Other Corp") }
  let(:admin_user)     { create(:user, :admin, customer: other_customer, email: "admin@it.test", password: "password123") }
  let(:member_user)    { create(:user, :member, customer: other_customer, email: "member@it.test", password: "password123") }

  let(:valid_industry) { "technology" }
  let(:valid_template_key) { PageLayoutTemplates.keys.first }

  def index_path
    admin_maintenance_platform_industry_templates_path(platform_customer.id)
  end

  def show_path(industry = valid_industry)
    admin_maintenance_platform_industry_template_path(platform_customer.id, id: industry)
  end

  def edit_path(industry = valid_industry)
    edit_admin_maintenance_platform_industry_template_path(platform_customer.id, id: industry)
  end

  def update_path(industry = valid_industry)
    admin_maintenance_platform_industry_template_path(platform_customer.id, id: industry)
  end

  let(:guard_path) { index_path }

  it_behaves_like "a platform-owner-guarded GET"

  describe "GET show — auth guards" do
    let(:guard_path) { show_path }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET edit — auth guards" do
    let(:guard_path) { edit_path }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "PATCH update — auth guards" do
    let(:guard_path) { update_path }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "GET show JSON auth" do
    it "is denied on show (JSON requests get 401)" do
      get show_path, as: :json
      expect(response).to have_http_status(:redirect).or have_http_status(:unauthorized)
    end
  end

  context "as non-owner admin" do
    before { sign_in admin_user }

    it "is denied on index" do
      get admin_maintenance_platform_industry_templates_path(other_customer.id)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    it "is denied on show" do
      get admin_maintenance_platform_industry_template_path(other_customer.id, id: valid_industry), as: :json
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    it "is denied on update" do
      patch admin_maintenance_platform_industry_template_path(other_customer.id, id: valid_industry),
            params: { template_keys: [valid_template_key] }
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  context "as member" do
    before { sign_in member_user }

    it "is denied on index" do
      get admin_maintenance_platform_industry_templates_path(other_customer.id)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  # -------------------------------------------------------------------
  # Happy path + branches (platform owner)
  # -------------------------------------------------------------------
  context "as platform owner" do
    before { sign_in platform_owner }

    describe "GET /index" do
      it "returns 200 for index and a valid-industry edit" do
        get index_path
        expect(response).to have_http_status(:ok)

        get edit_path
        expect(response).to have_http_status(:ok)
      end

      it "localizes industry names instead of titleize" do
        get index_path
        expect(response.body).to include(I18n.t("customers.industries.technology"))

        get edit_path
        expect(response.body).to include(I18n.t("customers.industries.technology"))
      end

      it "localizes industry names in zh-CN" do
        get index_path, params: { locale: "zh-CN" }
        expect(response.body).to include(I18n.t("customers.industries.technology", locale: :"zh-CN"))
        expect(response.body).to include(I18n.t("customers.industry_groups.technology_digital", locale: :"zh-CN"))

        get edit_path, params: { locale: "zh-CN" }
        expect(response.body).to include(I18n.t("customers.industries.technology", locale: :"zh-CN"))
      end
    end

    describe "GET /show" do
      it "returns JSON with industry and template_keys for a valid industry" do
        get show_path, as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["industry"]).to eq(valid_industry)
        expect(body["template_keys"]).to be_an(Array)
      end

      it "returns 404 JSON for an invalid industry" do
        get admin_maintenance_platform_industry_template_path(platform_customer.id, id: "not_an_industry"),
            as: :json
        expect(response).to have_http_status(:not_found)
        body = JSON.parse(response.body)
        expect(body["error"]).to match(/Invalid industry/i)
      end

      it "redirects for an invalid industry on HTML format" do
        get admin_maintenance_platform_industry_template_path(platform_customer.id, id: "not_an_industry")
        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to match(/Invalid industry/i)
      end
    end

    describe "GET /edit" do
      it "localizes existing category tabs and card badges in Chinese" do
        allow(PageLayoutTemplates).to receive(:all).and_return([{
          key: "catalog_locale_test", name: "Catalog locale fixture", description: "Catalog description", category: "general"
        }])
        expected = I18n.with_locale(:"zh-CN") { PageLayoutTemplates.category_label("general") }

        get edit_path, params: { locale: "zh-CN" }

        expect(response).to have_http_status(:ok)
        expect(expected).not_to eq(PageLayoutTemplates.categories.fetch("general").fetch(:label))
        document = Nokogiri::HTML(response.body)
        expect(document.at_css("button[data-category='general']").text.strip).to eq("#{expected} (1)")
        expect(document.at_css("label[data-category='general']").text.strip).to end_with(expected)
      end

      it "redirects with alert for an invalid industry" do
        get edit_admin_maintenance_platform_industry_template_path(platform_customer.id, id: "bogus_xyz")
        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to match(/Invalid industry/i)
      end
    end

    describe "PATCH /update" do
      before do
        IndustryTemplateMapping.where(industry: valid_industry).delete_all
      end

      it "replaces template mappings and redirects with notice" do
        patch update_path, params: { template_keys: [valid_template_key] }
        expect(response).to redirect_to(admin_maintenance_platform_industry_templates_path(platform_customer.id))
        expect(flash[:notice]).to eq(
          I18n.t("maint_platform.flash.industry_templates.mappings_updated",
                 industry: I18n.t("customers.industries.technology"))
        )
        expect(IndustryTemplateMapping.where(industry: valid_industry).pluck(:template_key)).to include(valid_template_key)
      end

      it "replaces template mappings and redirects with a localized notice" do
        patch update_path, params: { template_keys: [valid_template_key], locale: "zh-CN" }
        expect(response).to redirect_to(admin_maintenance_platform_industry_templates_path(platform_customer.id))
        expect(flash[:notice]).to eq(
          I18n.t("maint_platform.flash.industry_templates.mappings_updated",
                 locale: :"zh-CN",
                 industry: I18n.t("customers.industries.technology", locale: :"zh-CN"))
        )
      end

      it "replaces with empty list (clears all mappings) and redirects" do
        IndustryTemplateMapping.create!(industry: valid_industry, template_key: valid_template_key)
        patch update_path, params: { template_keys: [""] }
        expect(response).to redirect_to(admin_maintenance_platform_industry_templates_path(platform_customer.id))
        expect(IndustryTemplateMapping.where(industry: valid_industry).count).to eq(0)
      end

      it "redirects with alert instead of 500 when a template key is invalid" do
        patch update_path, params: { template_keys: ["not-a-real-template"] }
        expect(response).to redirect_to(edit_path)
        expect(flash[:alert]).to eq(I18n.t("maint_platform.flash.industry_templates.invalid_template_keys"))
      end

      it "does not 500 when template_keys is a scalar string" do
        patch update_path, params: { template_keys: "not-an-array" }

        expect(response).to have_http_status(:redirect)
      end

      it "redirects with alert for an invalid industry" do
        patch admin_maintenance_platform_industry_template_path(platform_customer.id, id: "bogus_xyz"),
              params: { template_keys: [valid_template_key] }
        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to match(/Invalid industry/i)
      end
    end
  end
end
