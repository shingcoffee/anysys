# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::Customers", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let!(:acme)              { create(:customer, name: "Acme Corp", alias: "AC") }
  let!(:beta)              { create(:customer, name: "Beta Inc", alias: "BI") }

  let(:platform_owner_user) { find_or_create_platform_owner }
  let(:platform_owner) { platform_owner_user }
  let(:platform_cid) { platform_customer.id }

  let(:other_customer) { create(:customer, name: "Other") }
  let(:non_owner_user) do
    create(:user, customer: other_customer, role: :member, email: "regular@other.test", password: "password123")
  end

  describe "GET index — auth guards" do
    let(:guard_path) { admin_maintenance_platform_customers_path(platform_cid) }

    it_behaves_like "a platform-owner-guarded GET"
    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "GET new — auth guards" do
    let(:guard_path) { new_admin_maintenance_platform_customer_path(platform_cid) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET show — auth guards" do
    let(:guard_path) { admin_maintenance_platform_customer_path(platform_cid, acme) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET edit — auth guards" do
    let(:guard_path) { edit_admin_maintenance_platform_customer_path(platform_cid, acme) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "PATCH update — auth guards" do
    let(:guard_path) { admin_maintenance_platform_customer_path(platform_cid, acme) }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "DELETE destroy — auth guards" do
    let(:guard_path) { admin_maintenance_platform_customer_path(platform_cid, acme) }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  describe "GET trash — auth guards" do
    let(:guard_path) { trash_admin_maintenance_platform_customers_path(platform_cid) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "DELETE empty_trash — auth guards" do
    let(:guard_path) { empty_trash_admin_maintenance_platform_customers_path(platform_cid) }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  describe "GET /index as platform owner" do
    before { sign_in platform_owner_user }

    it "returns 200 and lists all customers when search is blank" do
      get admin_maintenance_platform_customers_path(platform_customer.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Corp")
      expect(response.body).to include("Beta Inc")
    end

    it "filters by name token" do
      get admin_maintenance_platform_customers_path(platform_customer.id), params: { q: "acme" }

      table = Nokogiri::HTML(response.body).at_css("turbo-frame#admin-table")
      expect(table.text).to include("Acme Corp")
      expect(table.text).not_to include("Beta Inc")
    end

    it "filters by alias token (case-insensitive)" do
      get admin_maintenance_platform_customers_path(platform_customer.id), params: { q: "BI" }

      table = Nokogiri::HTML(response.body).at_css("turbo-frame#admin-table")
      expect(table.text).to include("Beta Inc")
      expect(table.text).not_to include("Acme Corp")
    end

    it "shows customer id and domain, with the short name under the customer" do
      acme.update_columns(domain: "acme.example.com")

      get admin_maintenance_platform_customers_path(platform_customer.id)

      document = Nokogiri::HTML(response.body)
      table = document.at_css("turbo-frame#admin-table")
      headers = table.css("thead th").map { |th| th.text.gsub(/\s+/, " ").strip }
      expect(headers).to eq([
        I18n.t("common.labels.customer"),
        I18n.t("chrome.customer_form.customer_id"),
        I18n.t("chrome.customer_form.domain"),
        I18n.t("common.labels.users"),
        I18n.t("common.labels.modules"),
        I18n.t("common.labels.created_at"),
        I18n.t("common.labels.actions")
      ])
      expect(document.at_css('input[type="search"]')["placeholder"]).to eq(
        I18n.t("maint_platform.customers.index.search_placeholder")
      )
      expect(table.text).to include(acme.id.to_s, "acme.example.com", "AC")
      expect(table.at_css("span.font-mono.break-all").text).to eq("acme.example.com")
      expect(table.css("span.font-mono.whitespace-nowrap").map(&:text)).to include(acme.id.to_s)
      expect(table.at_css("span.rounded-lg svg path")["d"]).to eq(AdminTableComponent::LEADING_ICONS[:building])

      beta_row = table.css("tbody tr").find { |row| row.text.include?("Beta Inc") }
      expect(beta_row.text).to include(beta.id.to_s, I18n.t("common.labels.em_dash"))
      expect(beta_row.text).not_to include("acme.example.com")
    end

    it "filters by customer id and domain" do
      acme.update_columns(domain: "acme.example.com")

      get admin_maintenance_platform_customers_path(platform_customer.id), params: { q: acme.id.to_s }

      table = Nokogiri::HTML(response.body).at_css("turbo-frame#admin-table")
      expect(table.text).to include("Acme Corp")
      expect(table.text).not_to include("Beta Inc")

      get admin_maintenance_platform_customers_path(platform_customer.id), params: { q: "ACME.EXAMPLE" }

      table = Nokogiri::HTML(response.body).at_css("turbo-frame#admin-table")
      expect(table.text).to include("Acme Corp", "acme.example.com")
      expect(table.text).not_to include("Beta Inc")
    end

    it "renders the search-empty state when no customer matches" do
      get admin_maintenance_platform_customers_path(platform_customer.id), params: { q: "zzz-no-match-zzz" }

      expect(response.body).to include("No matches for")
      expect(response.body).to include("zzz-no-match-zzz")
    end

    it "renders the customer table without a hostname section" do
      CustomDomainRecord.create!(hostname: "combined.example.com", customer_id: beta.id)
      get admin_maintenance_platform_customers_path(platform_cid), params: { q: "acme", target_customer_id: beta.id, edit_domain: "42" }

      document = Nokogiri::HTML(response.body)
      expect(document.css("h1").map { |node| node.text.strip }).to eq([I18n.t("maint_platform.customers.index.title")])
      expect(document.at_css('section[aria-labelledby="custom-domains-title"]')).to be_nil
      expect(document.css("#domain-form")).to be_empty
      expect(document.at_css("turbo-frame#admin-table").text).to include("Acme Corp")
      expect(document.text).not_to include("combined.example.com")
      expect(document.at_css('select[name="custom_domain[customer_id]"]')).to be_nil
    end

    it "keeps the search-empty state free of hostname management" do
      CustomDomainRecord.create!(hostname: "unfiltered.example.com", customer_id: beta.id)
      get admin_maintenance_platform_customers_path(platform_cid), params: { q: "zzz-no-match-zzz" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#admin-table").text).to include("zzz-no-match-zzz")
      expect(document.at_css('section[aria-labelledby="custom-domains-title"]')).to be_nil
      expect(document.text).not_to include("unfiltered.example.com")
    end

    it "returns the customer table for frame navigation without a hostname form" do
      get admin_maintenance_platform_customers_path(platform_cid),
          params: { q: "acme", sort: "name", dir: "desc", page: "1" }, headers: { "Turbo-Frame" => "admin-table" }

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css('head meta[name="turbo-visit-control"]')).to be_nil
      expect(document.at_css("#domain-form")).to be_nil
      expect(document.at_css("turbo-frame#admin-table").text).to include("Acme Corp")
    end

    it "rejects another URL CID before hostname reads despite a forged platform query CID" do
      expect(Customer).not_to receive(:domain_owner_id)
      expect(ModuleEntriesResolver).not_to receive(:call)

      get admin_maintenance_platform_customers_path(acme.id),
          params: { customer_id: 81721200, edit_domain: "42", target_customer_id: 81721200 }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /index as a non-platform-owner user" do
    before { sign_in non_owner_user }

    it "is denied" do
      get admin_maintenance_platform_customers_path(other_customer.id)

      expect(response).to have_http_status(:redirect)
    end
  end

  # ─── All remaining actions require platform owner ─────────────────────────

  describe "as platform owner" do
    before { sign_in platform_owner_user }

    let(:platform_cid) { platform_customer.id }

    # ── GET /index JSON format ────────────────────────────────────────────────

    it "GET index returns JSON" do
      expect(Customer).not_to receive(:domain_owner_id)
      get admin_maintenance_platform_customers_path(platform_cid), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_an(Array)
    end

    # ── GET /trash ────────────────────────────────────────────────────────────

    it "GET trash lists soft-deleted customers" do
      acme.soft_delete
      get trash_admin_maintenance_platform_customers_path(platform_cid)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Corp")
    end

    it "GET trash does not show active customers" do
      acme.soft_delete
      get trash_admin_maintenance_platform_customers_path(platform_cid)

      expect(response.body).not_to include("Beta Inc")
    end

    it "GET trash does not dump every deleted customer on one fake page" do
      first = create(:customer, name: "DumpA Customer")
      second = create(:customer, name: "DumpB Customer")
      first.soft_delete
      second.soft_delete

      get trash_admin_maintenance_platform_customers_path(platform_cid), params: { per_page: 1 }

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).css("tbody tr").size).to eq(1)
      expect(response.body).to include(
        I18n.t("maint_platform.customers.trash.empty_trash_confirm", count: Customer.only_deleted.count)
      )
    end

    # ── POST empty_trash ──────────────────────────────────────────────────────

    it "refuses to soft-delete the platform customer" do
      delete admin_maintenance_platform_customer_path(platform_cid, platform_customer)

      expect(response).to redirect_to(admin_maintenance_platform_customers_path(platform_cid))
      expect(flash[:alert]).to eq(I18n.t("maint_platform.flash.customers.platform_protected"))
      expect(platform_customer.reload.status).to eq("active")
    end

    it "omits move-to-trash on the platform customer profile" do
      get admin_maintenance_platform_customer_path(platform_cid, platform_customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(I18n.t("maint_platform.customers.show.move_to_trash"))
    end

    it "points Act as at the platform path and the target customer" do
      get admin_maintenance_platform_customers_path(platform_cid)

      href = admin_maintenance_platform_customer_context_path(platform_cid, target_customer_id: acme.id)
      expect(response.body).to include(CGI.escapeHTML(href))
    end

    it "DELETE empty_trash permanently deletes soft-deleted customers" do
      # Soft-delete a fresh customer so we can assert it's gone regardless of
      # other inactive customers that may exist from the test setup.
      to_purge = create(:customer, name: "Purge Me", alias: "PM", industry: :technology)
      to_purge.soft_delete
      count_before = Customer.only_deleted.count
      expect(count_before).to be >= 1

      delete empty_trash_admin_maintenance_platform_customers_path(platform_cid)

      expect(Customer.only_deleted.count).to eq(0)
      expect(response).to redirect_to(trash_admin_maintenance_platform_customers_path(platform_cid))
    end

    # ── GET /show, /new, /edit ────────────────────────────────────────────────

    it "GET show, new, and edit render HTML" do
      [
        admin_maintenance_platform_customer_path(platform_cid, acme),
        new_admin_maintenance_platform_customer_path(platform_cid),
        edit_admin_maintenance_platform_customer_path(platform_cid, acme)
      ].each do |path|
        get path
        expect(response).to have_http_status(:ok)
      end
    end

    it "GET show localizes created_at instead of ISO strftime" do
      get admin_maintenance_platform_customer_path(platform_cid, acme)
      expect(response.body).to include(I18n.l(acme.created_at, format: :long))
      expect(response.body).not_to include(acme.created_at.strftime("%Y-%m-%d %H:%M:%S"))
    end

    it "GET show localizes timestamps in zh-CN" do
      get admin_maintenance_platform_customer_path(platform_cid, acme), params: { locale: "zh-CN" }
      expect(response.body).to include(I18n.l(acme.created_at, format: :long, locale: :"zh-CN"))
    end

    it "GET show displays the domain beside the organization name and has no domain manager" do
      acme.update_columns(domain: "acme.example.com")
      get admin_maintenance_platform_customer_path(platform_cid, acme)

      document = Nokogiri::HTML(response.body)
      expect(document.text).to include("acme.example.com")
      expect(document.at_css("main a[href*='/domains']")).to be_nil
      expect(document.at_css("#domain-form")).to be_nil
    end

    it "GET show keeps an inactive customer's domain on the profile and does not offer edit" do
      acme.update_columns(domain: "acme.example.com")
      acme.soft_delete
      get admin_maintenance_platform_customer_path(platform_cid, acme)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.text).to include("acme.example.com")
      expect(document.at_css("main a[href*='/domains']")).to be_nil
      get edit_admin_maintenance_platform_customer_path(platform_cid, acme)
      expect(response).to have_http_status(:not_found)
    end

    it "GET show localizes industry instead of titleize" do
      get admin_maintenance_platform_customer_path(platform_cid, acme)
      expect(response.body).to include(I18n.t("customers.industries.technology"))
    end

    it "GET show localizes industry in zh-CN" do
      get admin_maintenance_platform_customer_path(platform_cid, acme), params: { locale: "zh-CN" }
      expect(response.body).to include(I18n.t("customers.industries.technology", locale: :"zh-CN"))
    end

    it "GET show returns JSON" do
      get admin_maintenance_platform_customer_path(platform_cid, acme), as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["id"]).to eq(acme.id)
    end

    # ── POST /create success ──────────────────────────────────────────────────

    it "POST create with valid params redirects and creates customer" do
      expect {
        post admin_maintenance_platform_customers_path(platform_cid),
             params: { customer: { name: "New Co", alias: "NC", industry: "technology" } }
      }.to change(Customer, :count).by(1)

      expect(response).to redirect_to(admin_maintenance_platform_customers_path(platform_cid))
    end

    it "POST create returns 201 JSON on success" do
      post admin_maintenance_platform_customers_path(platform_cid),
           params: { customer: { name: "Json Co", alias: "JC", industry: "technology" } }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["name"]).to eq("Json Co")
    end

    it "POST create persists the selected tenant locale" do
      post admin_maintenance_platform_customers_path(platform_cid),
           params: { customer: { name: "ZH Co", industry: "technology", locale: "zh-CN" } }

      expect(Customer.find_by(name: "ZH Co").locale).to eq("zh-CN")
    end

    it "PATCH update can set and clear the tenant locale" do
      patch admin_maintenance_platform_customer_path(platform_cid, acme),
            params: { customer: { locale: "zh-CN" } }
      expect(acme.reload.locale).to eq("zh-CN")

      patch admin_maintenance_platform_customer_path(platform_cid, acme),
            params: { customer: { locale: "" } }
      expect(acme.reload.locale).to be_nil
    end

    # ── POST /create failure ──────────────────────────────────────────────────

    it "POST create with blank name renders new with 422" do
      post admin_maintenance_platform_customers_path(platform_cid),
           params: { customer: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "POST create with blank name returns JSON errors on failure" do
      post admin_maintenance_platform_customers_path(platform_cid),
           params: { customer: { name: "" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_present
    end

    # ── PATCH /update success ─────────────────────────────────────────────────

    it "PATCH update with valid params redirects" do
      patch admin_maintenance_platform_customer_path(platform_cid, acme),
            params: { customer: { name: "Acme Renamed" } }

      expect(response).to redirect_to(admin_maintenance_platform_customer_path(platform_cid, acme))
      expect(acme.reload.name).to eq("Acme Renamed")
    end

    it "PATCH update returns JSON on success" do
      patch admin_maintenance_platform_customer_path(platform_cid, acme),
            params: { customer: { name: "Acme JSON" } }, as: :json

      expect(response).to have_http_status(:ok)
    end

    # ── PATCH /update failure ─────────────────────────────────────────────────

    it "PATCH update with blank name renders edit with 422" do
      patch admin_maintenance_platform_customer_path(platform_cid, acme),
            params: { customer: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "PATCH update with blank name returns JSON errors on failure" do
      patch admin_maintenance_platform_customer_path(platform_cid, acme),
            params: { customer: { name: "" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_present
    end

    # ── DELETE /destroy (soft delete) ─────────────────────────────────────────

    it "DELETE destroy soft-deletes the customer and redirects" do
      delete admin_maintenance_platform_customer_path(platform_cid, acme)

      expect(response).to redirect_to(admin_maintenance_platform_customers_path(platform_cid))
      expect(acme.reload.status).to eq("inactive")
    end

    it "DELETE destroy returns no_content JSON" do
      delete admin_maintenance_platform_customer_path(platform_cid, acme), as: :json

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "customer domain on the profile form" do
    let(:profile_path) { admin_maintenance_platform_customer_path(platform_cid, acme) }
    let(:profile_edit_path) { edit_admin_maintenance_platform_customer_path(platform_cid, acme) }

    before do
      sign_in platform_owner_user
      allow(CustomDomains::CnameVerifier).to receive(:call).and_return(:verified)
    end

    it "edits the domain on the same form as the organization name" do
      acme.update_columns(domain: "acme.example.com")
      get profile_edit_path

      document = Nokogiri::HTML(response.body)
      form = document.at_css('input[name="customer[domain]"]').ancestors("form").first
      expect(form["action"]).to eq(profile_path)
      expect(form.at_css('input[name="customer[domain]"]')["value"]).to eq("acme.example.com")
      expect(document.at_css("#domain-form")).to be_nil
      expect(document.at_css("main a[href*='/domains']")).to be_nil
    end

    it "saves a new domain with the rest of the profile" do
      patch profile_path, params: { customer: { name: "Acme Corp", domain: "NEW.Acme.Example." } }

      expect(response).to redirect_to(profile_path)
      expect(acme.reload).to have_attributes(name: "Acme Corp", domain: "new.acme.example")
      expect(CustomDomains::CnameVerifier).to have_received(:call).with(hostname: "new.acme.example")
    end

    it "clears the domain without a DNS check" do
      acme.update_columns(domain: "acme.example.com")
      expect(CustomDomains::CnameVerifier).not_to receive(:call)

      patch profile_path, params: { customer: { domain: "" } }

      expect(response).to redirect_to(profile_path)
      expect(acme.reload.domain).to be_nil
    end

    it "does not recheck DNS when the profile save leaves the domain unchanged" do
      acme.update_columns(domain: "acme.example.com")
      expect(CustomDomains::CnameVerifier).not_to receive(:call)

      patch profile_path, params: { customer: { name: "Renamed Acme", domain: "acme.example.com" } }

      expect(response).to redirect_to(profile_path)
      expect(acme.reload).to have_attributes(name: "Renamed Acme", domain: "acme.example.com")
    end

    it "rejects an invalid, taken, or unverified domain and keeps the typed value" do
      beta.update_columns(domain: "taken.example.com")

      patch profile_path, params: { customer: { domain: "https://bad.example/path" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("custom_domains.errors.invalid_domain"))
      expect(Nokogiri::HTML(response.body).at_css('input[name="customer[domain]"]')["value"]).to eq("https://bad.example/path")
      expect(acme.reload.domain).to be_nil

      patch profile_path, params: { customer: { domain: "TAKEN.Example.COM." } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("custom_domains.errors.domain_taken"))
      expect(acme.reload.domain).to be_nil

      allow(CustomDomains::CnameVerifier).to receive(:call).with(hostname: "fresh.example.com").and_return(:unverified)
      patch profile_path, params: { customer: { domain: "fresh.example.com" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("custom_domains.errors.cname_unverified"))
      expect(acme.reload.domain).to be_nil
    end

    it "returns domain errors as JSON" do
      patch profile_path, params: { customer: { domain: "not a domain" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].join).to include(I18n.t("custom_domains.errors.invalid_domain"))
    end

    it "has no dedicated domains route" do
      get "/81721200/admin/maintenance/platform/customers/#{acme.id}/domains"
      expect(response).to have_http_status(:not_found)
    end

    it "rejects JSON show and update outside the actual platform URL prefix" do
      path = admin_maintenance_platform_customer_path(beta.id, acme)
      get path, as: :json
      expect(response).to have_http_status(:not_found)

      patch path, params: { customer: { name: "Existing JSON Interface" } }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(acme.reload.name).to eq("Acme Corp")
    end

    %i[index show edit update].each do |surface|
      it "rejects wrong-prefix #{surface} before changing the customer" do
        path = if surface == :index
          admin_maintenance_platform_customers_path(beta.id)
        elsif surface == :edit
          edit_admin_maintenance_platform_customer_path(beta.id, acme)
        else
          admin_maintenance_platform_customer_path(beta.id, acme)
        end
        if surface == :update
          patch path, params: { customer: { name: "Forged Profile", domain: "forged.example.com" } }
        else
          get path
        end
        expect(response).to have_http_status(:not_found)
        expect(acme.reload.name).to eq("Acme Corp")
        expect(acme.domain).to be_nil
      end
    end
  end

  # ── Non-owner denied for all write actions ──────────────────────────────────

  describe "non-owner is denied all write actions" do
    before { sign_in non_owner_user }

    it "POST create is denied" do
      post admin_maintenance_platform_customers_path(other_customer.id),
           params: { customer: { name: "Hijack" } }
      expect(response).to have_http_status(:redirect)
    end

    it "PATCH update is denied" do
      patch admin_maintenance_platform_customer_path(other_customer.id, acme),
            params: { customer: { name: "Hijack" } }
      expect(response).to have_http_status(:redirect)
    end

    it "DELETE destroy is denied" do
      delete admin_maintenance_platform_customer_path(other_customer.id, acme)
      expect(response).to have_http_status(:redirect)
    end
  end
end
