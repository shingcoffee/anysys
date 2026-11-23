# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::Sms::Templates", type: :request do
  let(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)    { find_or_create_platform_owner }

  before do
    Current.customer = platform_customer
    sign_in platform_owner
  end

  let(:base_path)  { "/#{platform_customer.id}/admin/maintenance/platform/module_settings/sms/templates" }
  let(:guard_path) { base_path }
  let(:index_path) { admin_maintenance_platform_module_settings_sms_templates_path(customer_id: platform_customer.id) }

  it_behaves_like "a platform-owner-guarded GET"
  it_behaves_like "a platform-owner-guarded request", :post

  describe "GET new — auth guards" do
    let(:guard_path) { "#{base_path}/new" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET edit — auth guards" do
    let!(:template) { create(:sms_template, key: "guard_edit") }
    let(:guard_path) { "#{base_path}/#{template.id}/edit" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "PATCH update — auth guards" do
    let!(:template) { create(:sms_template, key: "guard_update") }
    let(:guard_path) { "#{base_path}/#{template.id}" }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "DELETE destroy — auth guards" do
    let!(:template) { create(:sms_template, key: "guard_delete") }
    let(:guard_path) { "#{base_path}/#{template.id}" }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  # ---------------------------------------------------------------------------
  # GET index
  # ---------------------------------------------------------------------------

  describe "GET index" do
    let!(:template) { create(:sms_template, key: "welcome_msg", variables: %w[name]) }

    it "returns 200 and lists templates" do
      get base_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("welcome_msg")
    end

    it "localizes updated_at instead of ISO strftime" do
      get base_path
      expect(response.body).to include(I18n.l(template.updated_at, format: :long))
      expect(response.body).not_to include(template.updated_at.strftime("%Y-%m-%d %H:%M"))
    end

    it "localizes updated_at in zh-CN" do
      get base_path, params: { locale: "zh-CN" }
      expect(response.body).to include(I18n.l(template.updated_at, format: :long, locale: :"zh-CN"))
    end

    it "renders search and sortable headers while preserving q, sort, and dir" do
      get base_path, params: { q: "welcome", sort: "key", dir: "asc" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('type="search"')
      expect(response.body).to include('name="q"')
      expect(response.body).to include('value="welcome"')

      document = Nokogiri::HTML(response.body)
      key_link = document.at_css("[data-sms-template-sort='key']")
      status_link = document.at_css("[data-sms-template-sort='status']")
      updated_link = document.at_css("[data-sms-template-sort='updated_at']")

      expect(key_link["href"]).to include("q=welcome", "sort=key", "dir=desc")
      expect(status_link["href"]).to include("q=welcome", "sort=status", "dir=asc")
      expect(updated_link["href"]).to include("q=welcome", "sort=updated_at", "dir=asc")

      key_header = key_link.ancestors("[role='columnheader']").first
      status_header = status_link.ancestors("[role='columnheader']").first
      updated_header = updated_link.ancestors("[role='columnheader']").first
      expect(key_header["aria-sort"]).to eq("ascending")
      expect(status_header["aria-sort"]).to eq("none")
      expect(updated_header["aria-sort"]).to eq("none")

      mobile_sort = document.at_css("nav[aria-label='#{I18n.t("maint_platform.sms.templates.index.sort_label")}']")
      expect(mobile_sort["data-responsive-collection-mobile-sort"]).to eq("true")
      expect(mobile_sort.text).to include(I18n.t("maint_platform.sms.templates.index.current_sort",
                                                column: I18n.t("common.labels.key"),
                                                direction: I18n.t("maint_platform.sms.templates.index.sort_directions.asc")))
    end

    it "renders one responsive record with one edit and delete action" do
      get base_path

      document = Nokogiri::HTML(response.body)
      record = document.at_css("[data-responsive-collection-record='#{template.id}']")
      edit_path = edit_admin_maintenance_platform_module_settings_sms_template_path(
        customer_id: platform_customer.id, id: template.id
      )
      delete_path = admin_maintenance_platform_module_settings_sms_template_path(
        customer_id: platform_customer.id, id: template.id
      )

      expect(document.css("[data-responsive-collection-record='#{template.id}']").size).to eq(1)
      expect(record["role"]).to eq("row")
      expect(record.element_children.count { |child| child["role"] == "cell" }).to eq(6)
      expect(record.css("a[href='#{edit_path}']").size).to eq(1)
      expect(record.css("a[href='#{delete_path}'][data-turbo-method='delete']").size).to eq(1)
      expect(record.at_css("a[href='#{delete_path}']")["data-turbo-confirm"]).to eq(
        I18n.t("maint_platform.sms.templates.index.delete_confirm")
      )
    end
  end

  # ---------------------------------------------------------------------------
  # GET new and edit
  # ---------------------------------------------------------------------------

  describe "GET new and edit" do
    let!(:template) { create(:sms_template, key: "edit_target") }

    it "returns 200 for the new and edit forms" do
      get "#{base_path}/new"
      expect(response).to have_http_status(:ok)

      get "#{base_path}/#{template.id}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("edit_target")
    end
  end

  # ---------------------------------------------------------------------------
  # POST create — success
  # ---------------------------------------------------------------------------

  describe "POST create — success" do
    it "creates a template with per-provider codes and a parsed variables list, then redirects" do
      post base_path, params: {
        sms_template: {
          key: "verify_code", description: "test", status: "active", variables_raw: "code, minutes",
          provider_template_codes: { aliyun: "SMS_1", twilio: "HX1" }
        }
      }
      expect(response).to redirect_to(index_path)
      t = Sms::Template.find_by(key: "verify_code")
      expect(t.variables).to eq(%w[code minutes])
      expect(t.provider_code("aliyun")).to eq("SMS_1")
      expect(t.provider_code("twilio")).to eq("HX1")
    end

    it "drops blank provider codes rather than persisting empty strings" do
      post base_path, params: {
        sms_template: {
          key: "blank_code_test", status: "active", variables_raw: "",
          provider_template_codes: { aliyun: "SMS_2", twilio: "" }
        }
      }
      t = Sms::Template.find_by(key: "blank_code_test")
      expect(t.provider_codes).to eq("aliyun" => "SMS_2")
    end
  end

  # ---------------------------------------------------------------------------
  # POST create — failure (blank key fails validation)
  # ---------------------------------------------------------------------------

  describe "POST create — invalid params" do
    it "re-renders new with 422" do
      post base_path, params: {
        sms_template: { key: "", status: "active", variables_raw: "",
                        provider_template_codes: { aliyun: "" } }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "re-renders new with 422 when every provider code is blank" do
      post base_path, params: {
        sms_template: { key: "no_codes", status: "active", variables_raw: "",
                        provider_template_codes: { aliyun: "", twilio: "" } }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH update — success
  # ---------------------------------------------------------------------------

  describe "PATCH update — success" do
    let!(:template) { create(:sms_template, key: "update_me", variables: %w[code]) }

    it "updates the template and redirects" do
      patch "#{base_path}/#{template.id}", params: {
        sms_template: { key: "update_me", status: "active", variables_raw: "code, expiry",
                        provider_template_codes: { aliyun: "SMS_99" } }
      }
      expect(response).to redirect_to(index_path)
      expect(template.reload.variables).to eq(%w[code expiry])
      expect(template.provider_code("aliyun")).to eq("SMS_99")
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH update — failure
  # ---------------------------------------------------------------------------

  describe "PATCH update — invalid params" do
    let!(:template) { create(:sms_template, key: "update_fail") }

    it "re-renders edit with 422" do
      patch "#{base_path}/#{template.id}", params: {
        sms_template: { key: "", status: "active", provider_template_codes: { aliyun: "" } }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy — retire when messages exist
  # ---------------------------------------------------------------------------

  describe "DELETE destroy — retires template with messages" do
    it "updates status to retired and redirects" do
      t = create(:sms_template, key: "rx", variables: %w[code])
      create(:sms_message, customer: platform_customer, sms_template: t,
             template_key: "rx", vars: { "code" => "1" })

      delete "#{base_path}/#{t.id}"
      expect(response).to redirect_to(index_path)
      expect(t.reload.status).to eq("retired")
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy — hard delete when no messages
  # ---------------------------------------------------------------------------

  describe "DELETE destroy — hard-deletes template with no messages" do
    it "removes the record entirely" do
      t = create(:sms_template, key: "unused", variables: [])
      delete "#{base_path}/#{t.id}"
      expect(Sms::Template.exists?(t.id)).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy — concurrent message creation trips the restrict guard
  # ---------------------------------------------------------------------------

  describe "DELETE destroy — a message created concurrently raises DeleteRestrictionError" do
    it "falls back to retiring the template gracefully rather than 500ing" do
      t = create(:sms_template, key: "racey", variables: [])
      # exists? sees no messages, then destroy! trips restrict_with_exception.
      allow_any_instance_of(Sms::Template).to receive(:destroy!)
        .and_raise(ActiveRecord::DeleteRestrictionError.new("sms_messages"))

      delete "#{base_path}/#{t.id}"

      expect(response).to redirect_to(index_path)
      expect(t.reload.status).to eq("retired")
    end
  end
end
