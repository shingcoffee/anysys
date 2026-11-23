# frozen_string_literal: true

require "rails_helper"

# Export real, authorized test-DB responses for conditional browser states absent
# from the development customer. No fixtures or mutation routes touch development.
# SETTINGS_BROWSER_FIXTURES=1 bundle exec rspec spec/system/admin/settings/customer_settings_browser_fixtures_spec.rb
RSpec.describe "Customer settings conditional browser fixtures", type: :system do
  def page ; Capybara.current_session ; end

  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }

  before do
    raise "Test database required" unless Rails.env.test?
    if ENV["SETTINGS_BROWSER_FIXTURES"] == "1"
      expected = Pathname.new(ENV.fetch("E2E_DATABASE_PATH")).expand_path(Rails.root)
      actual = Pathname.new(ActiveRecord::Base.connection_db_config.database).expand_path(Rails.root)
      raise "Separate app-local exporter database required" unless actual == expected &&
        expected.dirname == Rails.root.join("storage").realpath && expected.basename.to_s.start_with?("e2e")
    end
    sign_in admin
  end

  def verify_and_export(name, path, locale)
    visit "#{path}?locale=#{locale}"
    expect(page.status_code).to eq(200)
    expect(page).to have_xpath("//main[@id='main-content']//h1[not(ancestor::*[@data-settings-page])]", count: 1)
    expect(page).to have_css("main a[href='/#{customer.id}/admin/settings']")
    return unless ENV["SETTINGS_BROWSER_FIXTURES"] == "1"

    directory = Pathname.new(ENV.fetch("EXPORT_CUSTOMER_SETTINGS_FIXTURES", "tmp/playwright-customer-settings/fixtures")).expand_path(Rails.root)
    raise "App-local tmp export directory required" unless directory.to_s.start_with?(Rails.root.join("tmp").to_s + "/")
    FileUtils.mkdir_p(directory)
    File.write(directory.join("#{name}-#{locale}.json"), {
      path: path, locale: locale, html: page.html, customer_id: customer.id,
      source: "spec/system/admin/settings/customer_settings_browser_fixtures_spec.rb", schema_version: 1
    }.to_json)
  end

  %w[en zh-CN].each do |locale|
    it "renders populated website footer controls in #{locale}" do
      enable_module!("website", customer, name: "Website")
      create(:website, customer: customer, name: "QA website", footer: {
        "columns" => [
          { "heading" => "Visit", "links" => [{ "label" => "About", "url" => "/about" }] },
          { "heading" => "Help", "links" => [{ "label" => "Contact", "url" => "/contact" }] }
        ]
      })
      verify_and_export("website-footer", "/#{customer.id}/admin/settings/modules/website", locale)
      expect(page).to have_css("[data-footer-columns] > li", count: 2)
      expect(page).to have_field("website_footer_column_new_heading")
    end

    it "renders reserved member-role edit and grants controls in #{locale}" do
      role = customer.roles.find_by!(key: "member")
      base = "/#{customer.id}/admin/settings/modules/authentication/roles/#{role.id}"
      verify_and_export("role-edit", "#{base}/edit", locale)
      expect(page).to have_field("role[name]", with: role.name)
      verify_and_export("role-grants", "#{base}/grants", locale)
      expect(page).to have_css("[data-controller='grants-editor']")
      expect(page).to have_css("[data-grants-editor-locked-value='true']")
      expect(page).not_to have_css("[data-grants-editor-target='checkbox']:not([disabled])")
    end

    it "renders provisioned payment providers and both environments in #{locale}" do
      Payments::PlatformGateway.for_provider("stripe").update!(available: true)
      enable_module!("payment", customer, name: "Payments")
      FeatureModules::Payment::Provisioner.call(customer)
      accounts = Payments::MerchantAccount.unscoped_by_tenant.where(customer: customer, provider: "stripe").index_by(&:mode)
      expect(accounts.keys).to contain_exactly("sandbox", "production")
      base = "/#{customer.id}/admin/settings/modules/payments/merchant_accounts"
      verify_and_export("payment-providers", base, locale)
      expect(page).to have_css("[data-controller='payments--gateway-toggle'] input:not([disabled])")
      accounts.each do |mode, account|
        verify_and_export("payment-#{mode}", "#{base}/#{account.id}/edit", locale)
        expect(page).to have_css("form[data-controller='payments--gateway-config']")
        expect(page).to have_css("[data-mode='#{mode}'][aria-current='page']")
      end
    end

    it "renders this tenant's public-page protection controls in #{locale}" do
      enable_module!("captcha", customer, name: "Captcha")
      entity = create(:entity, :with_name_status_schema, customer: customer)
      create(:page, :for_member, :for_public, customer: customer, entity: entity, name: "QA public page")
      verify_and_export("public-protection", "/#{customer.id}/admin/settings/modules/captcha", locale)
      expect(page).to have_css("form[data-controller='captcha-throttle-picker']", count: 1)
      expect(page).to have_css("[data-captcha-page-list-target='row']", text: "QA public page")
    end

    it "renders tenant user access with only the three reserved role choices in #{locale}" do
      create(:user, :member, customer: customer, email: "qa-member@example.test")
      verify_and_export("user-access", "/#{customer.id}/admin/settings/modules/authentication/user_role_assignments", locale)
      expect(page).to have_css("button[data-controller='user-role-dialog']", minimum: 2)
      expect(customer.roles.pluck(:key)).to contain_exactly("owner", "admin", "member")
    end

    it "renders custom email personalization edit with the persisted mapping in #{locale}" do
      enable_module!("email", customer, name: "Email")
      entity = create(:entity, :with_name_status_schema, customer: customer, name: "QA contacts")
      token = create(:email_template_token, customer: customer, entity: entity, label: "QA contact name", attribute_slug: "name")
      verify_and_export("token-edit", "/#{customer.id}/admin/settings/modules/emails/template_tokens/#{token.id}/edit", locale)
      expect(page).to have_field("emails_template_token[label]", with: token.label)
      expect(page).to have_select("emails_template_token[attribute_slug]", selected: "Name")
    end

    it "renders customer invoice list, detail and opt-in printable download in #{locale}" do
      # Current customer callbacks already onboard one live subscription.
      subscription = Billing::Subscription.find_by(customer: customer) ||
        create(:billing_subscription, customer: customer, plan: create(:billing_plan))
      invoice = create(:billing_invoice, :open, :paid, customer: customer, subscription: subscription,
                       number: "INV-QA-SETTINGS", total_cents: 9900, currency: "CNY")
      base = "/#{customer.id}/admin/settings/billing/invoices"
      verify_and_export("invoice-list", base, locale)
      expect(page).to have_text(invoice.number)
      verify_and_export("invoice-detail", "#{base}/#{invoice.id}", locale)
      expect(page).to have_link(href: "#{base}/#{invoice.id}/download")
      expect(page).not_to have_css("form[action*='/maintenance/platform/']")
      verify_and_export("invoice-download", "#{base}/#{invoice.id}/download", locale)
      expect(page).to have_text(Billing::CurrencyResolver.format(9900, "CNY"))
      expect(page).to have_css("[data-shell-workspace]")
    end
  end
end
