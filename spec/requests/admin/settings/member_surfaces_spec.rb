# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Settings — Member Surface", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments" }

  before do
    enable_module!("payment", customer, name: "Payments")
  end

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :patch

  describe "GET .../sources/modules/surfaces/payments" do
    it "renders the per-surface form" do
      get "/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payments")
      expect(response.body).to include("Save")
    end
  end

  describe "GET .../sources/entities/surfaces/:key" do
    let!(:course) { create(:entity, customer: customer, name: "Course") }
    let(:guard_path) { "/#{customer.id}/admin/settings/member/sources/entities/surfaces/entity_#{course.id}" }

    it_behaves_like "an admin-guarded GET"

    it "renders the entity surface form" do
      get guard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Course")
    end
  end

  describe "GET with mismatched source/surface" do
    let(:guard_path) { "/#{customer.id}/admin/settings/member/sources/builtin/surfaces/payments" }

    it_behaves_like "an admin-guarded GET"

    it "404s when surface does not belong to source" do
      get "/#{customer.id}/admin/settings/member/sources/builtin/surfaces/payments"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH .../sources/modules/surfaces/payments" do
    it "submits explicit empty visibility lists from the full display form while retaining locked choices" do
      patch guard_path, params: { member_settings: { rows: [{
        surface_key: "payments", enabled: "1", label: "Donations",
        visible_column_keys: %w[date amount], visible_section_keys: %w[primary],
        visible_detail_row_keys: %w[amount]
      }] } }
      expect(response).to redirect_to(guard_path)
      get guard_path
      form = Nokogiri::HTML(response.body).at_css('[data-settings-page] form')
      visibility_keys = %w[visible_column_keys visible_section_keys visible_detail_row_keys]
      pairs = form.css("input[name], select[name], textarea[name]").filter_map do |field|
        next if field["disabled"]
        if field["type"] == "checkbox"
          next if visibility_keys.any? { |key| field["name"].include?(key) } || !field["checked"]
        end
        value = case field.name
                when "select" then field.at_css("option[selected]")&.[]("value")
                when "textarea" then field.text
                else field["value"]
                end
        [field["name"], value]
      end
      visibility_keys.each do |key|
        expect(pairs).to include(["member_settings[rows][0][#{key}][]", ""])
      end

      post form["action"], params: URI.encode_www_form(pairs),
           headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

      expect(response).to redirect_to(guard_path)
      setting = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
      expect(setting.label_or("fallback")).to eq("Donations")
      visibility_keys.each do |key|
        locked_values = pairs.select { |name, value| name == "member_settings[rows][0][#{key}][]" && value.present? }.map(&:last)
        # The sentinel communicates an explicit empty selection; normalization
        # removes it while preserving server-locked choices.
        expect(setting.config_json.fetch(key)).to eq(locked_values)
      end
      get guard_path
      fields = Nokogiri::HTML(response.body).css('[data-settings-page] input[type="checkbox"]')
      visibility_fields = fields.select { |field| visibility_keys.any? { |key| field["name"].include?(key) } }
      expect(visibility_fields.reject { |field| field["disabled"] }.map { |field| field["checked"] }).to all(be_nil)
      expect(visibility_fields.select { |field| field["disabled"] }.map { |field| field["checked"] }).to all(be_present)
    end

    it "saves the overlay and round-trips on next GET" do
      patch "/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments",
            params: {
              member_settings: {
                rows: [{ surface_key: "payments", enabled: "1", label: "Donations", per_page: "5" }]
              }
            }
      expect(response).to redirect_to("/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments")

      get "/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments"
      expect(response.body).to include("Donations")
    end

    it "returns 422 on invalid input" do
      patch "/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments",
            params: {
              member_settings: {
                rows: [{ surface_key: "payments", enabled: "1", per_page: "999999" }]
              }
            }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not 500 when a row is a scalar string" do
      patch "/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments",
            params: { member_settings: { rows: ["x"] } }

      expect(response).to have_http_status(:redirect)
    end
  end

  describe "PATCH row action on an entity surface" do
    let!(:course) { create(:entity, customer: customer, name: "Course") }
    let(:surface_key) { "entity_#{course.id}" }
    let(:guard_path) { "/#{customer.id}/admin/settings/member/sources/entities/surfaces/#{surface_key}" }

    def row_action_params(overrides = {})
      {
        member_settings: {
          rows: [{
            surface_key: surface_key, enabled: "1",
            row_action_key: "enroll", row_action_field: "course", row_action_label: "Enroll"
          }.merge(overrides)]
        }
      }
    end

    it_behaves_like "an admin-guarded request", :patch

    it "saves the row action overlay" do
      create(:page, :launched, :member_only, customer: customer, action_key: "enroll")

      patch guard_path, params: row_action_params
      expect(response).to redirect_to(guard_path)

      setting = Member::SurfaceSetting.find_by!(customer: customer, surface_key: surface_key)
      expect(setting.row_action_or("Open")).to eq(
        action_key: "enroll", field: "course", label: "Enroll"
      )
    end

    it "returns 422 with row_action_invalid when the pair is incomplete" do
      patch guard_path, params: row_action_params(row_action_field: "")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("admin_settings.errors.validations.row_action_invalid"))
    end

    it "forbids a member from posting Settings / Member params" do
      sign_in create(:user, :member, customer: customer)
      patch guard_path, params: row_action_params

      expect(response).to have_http_status(:forbidden)
        .or have_http_status(:found)
        .or have_http_status(:not_found)
      expect(Member::SurfaceSetting.find_by(customer: customer, surface_key: surface_key)).to be_nil
    end

    it "rejects another tenant's admin without writing this customer's overlay" do
      other_customer = create(:customer)
      other_admin = create(:user, :admin, customer: other_customer)
      sign_in other_admin

      patch guard_path, params: row_action_params

      expect(response).to redirect_to(Authentication::LandingPath.for(other_admin))
      expect(Member::SurfaceSetting.find_by(customer: customer, surface_key: surface_key)).to be_nil
    end
  end

  describe "PATCH on built-in surface" do
    let(:guard_path) { "/#{customer.id}/admin/settings/member/sources/builtin/surfaces/builtin_home" }

    it_behaves_like "an admin-guarded request", :patch

    it "returns 403" do
      patch "/#{customer.id}/admin/settings/member/sources/builtin/surfaces/builtin_home",
            params: { member_settings: { rows: [{ surface_key: "builtin_home", enabled: "0" }] } }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET .../sources/builtin/surfaces/builtin_home" do
    it "renders a read-only settings page instead of 500" do
      get "/#{customer.id}/admin/settings/member/sources/builtin/surfaces/builtin_home"
      expect(response).to have_http_status(:ok)
    end

    it "uses the source name in the breadcrumb instead of titleizing the key" do
      get "/#{customer.id}/admin/settings/member/sources/builtin/surfaces/builtin_home"
      expect(Capybara.string(response.body)).to have_link(
        I18n.t("settings_people.sources.builtin.name"),
        href: "/#{customer.id}/admin/settings/member/sources/builtin"
      )
      expect(response.body).not_to include(">Builtin<")
    end

    it "localizes the source breadcrumb in zh-CN" do
      get "/#{customer.id}/admin/settings/member/sources/builtin/surfaces/builtin_home",
          params: { locale: "zh-CN" }
      expect(response.body).to include(
        I18n.t("settings_people.sources.builtin.name", locale: :"zh-CN")
      )
    end
  end
end
