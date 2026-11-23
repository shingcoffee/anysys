# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Settings — Member Source", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/settings/member/sources/modules" }

  before do
    enable_module!("payment", customer, name: "Payments")
  end

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :patch

  describe "GET .../sources/builtin" do
    let(:guard_path) { "/#{customer.id}/admin/settings/member/sources/builtin" }

    it_behaves_like "an admin-guarded GET"

    it "renders core pages as always available without display editors or toggles" do
      get "/#{customer.id}/admin/settings/member/sources/builtin"
      expect(response).to have_http_status(:ok)
      page = Capybara.string(response.body)
      expect(page).to have_text(I18n.t("settings_people.always_available"))
      expect(page).not_to have_link(I18n.t("settings_people.display_settings"))
      expect(page).not_to have_css('input[name^="member_settings"]')
    end
  end

  describe "GET .../sources/modules" do
    it "renders the source row list" do
      get "/#{customer.id}/admin/settings/member/sources/modules"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payments")
      expect(Capybara.string(response.body)).to have_link(
        I18n.t("settings_people.display_settings"),
        href: "/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments"
      )
    end
  end

  describe "GET .../sources/entities" do
    let(:guard_path) { "/#{customer.id}/admin/settings/member/sources/entities" }
    let!(:course) { create(:entity, customer: customer, name: "Course") }

    it_behaves_like "an admin-guarded GET"

    it "renders entity-backed surfaces" do
      get "/#{customer.id}/admin/settings/member/sources/entities"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Course")
    end
  end

  describe "PATCH .../sources/entities" do
    let(:guard_path) { "/#{customer.id}/admin/settings/member/sources/entities" }
    let!(:course) { create(:entity, customer: customer, name: "Course") }

    it_behaves_like "an admin-guarded request", :patch
  end

  describe "PATCH .../sources/builtin" do
    let(:guard_path) { "/#{customer.id}/admin/settings/member/sources/builtin" }

    it_behaves_like "an admin-guarded request", :patch

    it "returns 403 because the source is not editable" do
      patch "/#{customer.id}/admin/settings/member/sources/builtin",
            params: { member_settings: { rows: [{ surface_key: "builtin_home", enabled: "0" }] } }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH .../sources/modules" do
    it "rejects a cross-tenant admin's toggle without changing either customer's settings" do
      other_customer = create(:customer)
      enable_module!("payment", other_customer)
      settings = [customer, other_customer].map do |tenant|
        Member::SurfaceSetting.create!(customer: tenant, surface_key: "payments", source_key: "modules", enabled: true)
      end
      other_admin = create(:user, :admin, customer: other_customer)
      sign_in other_admin

      patch guard_path, params: { member_settings: { rows: [{ surface_key: "payments", enabled: "0" }] } }

      expect(response).to redirect_to(Authentication::LandingPath.for(other_admin))
      expect(settings.map { |setting| setting.reload.enabled }).to eq([true, true])
    end

    it "preserves customized display fields when submitting the rendered visibility toggle off and on" do
      setting = Member::SurfaceSetting.new(
        customer: customer, surface_key: "payments", source_key: "modules", enabled: true, position: 50
      )
      setting.write_overlay(
        label: "Donations", icon: :heart, subtitle: "Past donations", per_page: 5,
        empty_headline: "No donations yet", empty_body: "Your donations appear here.",
        visible_column_keys: %w[date amount], visible_section_keys: %w[primary],
        visible_detail_row_keys: %w[amount]
      )
      setting.save!
      saved_config = setting.config_json.deep_dup

      [false, true].each do |enabled|
        get guard_path
        expect(response).to have_http_status(:ok)
        form = Nokogiri::HTML(response.body).at_css('form[data-controller="auto-submit"]')
        expect(form).to be_present
        expect(form.at_css('input[type="checkbox"]')["data-action"]).to eq("change->auto-submit#submit")
        inputs = form.css("input[name]").reject do |input|
          input["disabled"] || (input["type"] == "checkbox" && !enabled)
        end
        payload = URI.encode_www_form(inputs.map { |input| [input["name"], input["value"]] })
        row_params = Rack::Utils.parse_nested_query(payload).fetch("member_settings").fetch("rows").fetch("0")
        expect(row_params).to eq("surface_key" => "payments", "enabled" => enabled ? "1" : "0")

        post form["action"], params: payload,
             headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

        expect(response).to redirect_to(guard_path)
        expect(setting.reload.enabled).to eq(enabled)
        expect(setting.position).to eq(50)
        expect(setting.config_json).to eq(saved_config)
      end
    end

    it "persists an inline toggle" do
      patch "/#{customer.id}/admin/settings/member/sources/modules",
            params: {
              member_settings: {
                rows: [{ surface_key: "payments", enabled: "0" }]
              }
            }
      expect(response).to redirect_to("/#{customer.id}/admin/settings/member/sources/modules")
      row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
      expect(row.enabled).to be(false)
    end
  end

  describe "GET .../sources/phantom" do
    let(:guard_path) { "/#{customer.id}/admin/settings/member/sources/phantom" }

    it_behaves_like "an admin-guarded GET"

    it "404s on unknown source" do
      get "/#{customer.id}/admin/settings/member/sources/phantom"
      expect(response).to have_http_status(:not_found)
    end
  end
end
