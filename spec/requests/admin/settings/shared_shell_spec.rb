# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Customer settings shared shell", type: :request do
  include_context "as admin"

  let(:root) { "/#{customer.id}/admin/settings" }
  let(:destinations) do
    groups = {
      members: {
        member_portal: "/member"
      },
      ai_assistant: { ai_assistant: "/modules/ai_assistant" },
      captcha: { public_page_protection: "/modules/captcha" },
      email: {
        email_sending_limit: "/modules/emails/daily_cap",
        email_personalization: "/modules/emails/template_tokens"
      },
      payment: { payment_providers: "/modules/payments/merchant_accounts" },
      sms: { sms_sending_limit: "/modules/sms/daily_cap" },
      authentication: {
        member_registration: "/modules/authentication/sign_up",
        password_reset: "/modules/authentication/forget_password",
        roles_permissions: "/modules/authentication/roles",
        user_access: "/modules/authentication/user_role_assignments",
        account_security: "/modules/authentication"
      },
      website: { website: "/modules/website" },
      billing: {
        plan_subscription: "/billing/subscription",
        billing_payment_methods: "/billing/payment_methods", invoices: "/billing/invoices"
      }
    }
    %i[authentication website payment email sms captcha ai_assistant members billing].to_h do |key|
      [key, groups.fetch(key)]
    end
  end
  let(:account) { create(:payment_merchant_account, :alipay, customer: customer) }
  let(:entity) { create(:entity, :with_name_status_schema, customer: customer) }
  let(:token) { create(:email_template_token, customer: customer, entity: entity) }
  let(:invoice) do
    subscription = create(:billing_subscription, customer: customer)
    create(:billing_invoice, :open, customer: customer, subscription: subscription)
  end

  before do
    %w[authentication website ai_assistant email sms captcha payment].each do |key|
      enable_module!(key, customer)
    end
  end

  def settings_navs(document, locale)
    # These assertions cover the three full task menus. The collapsed icon rail
    # shares their accessible name but exposes section-expansion buttons rather
    # than leaf destinations; its own behavior is checked separately below.
    document.css("nav").select do |nav|
      nav["aria-label"] == I18n.t("chrome.menu_bar.items.settings", locale: locale) &&
        nav.ancestors('[data-sidebar-collapsible-target="rail"]').empty?
    end
  end

  def group_nodes(container)
    if container["data-settings-catalog"]
      container.css("section[aria-labelledby^='catalog-']")
    else
      container.css('[data-list-filter-target="group"]')
    end
  end

  # Category headings (h3) and group labels; the summary's aria-hidden spans are
  # its icon tile and destination count.
  def label_text(node)
    node.at_css("h2, h3, p, summary span:not([aria-hidden])")&.text&.strip
  end

  def group_label(group, locale)
    return I18n.t("settings_navigation.groups.#{group}", locale: locale) if %i[members billing].include?(group)

    I18n.t("feature_modules.#{group}.name", locale: locale)
  end

  def expect_shell(path, active_path:, locale:, title: nil)
    get path, params: { locale: locale }
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css("h1").size).to eq(1)
    expect(document.at_css("h1").text.strip).to eq(title) if title
    expect(document.css("[data-settings-page]").size).to eq(1)
    breadcrumbs = document.css("nav").find { |nav| nav["aria-label"] == I18n.t("common.aria.breadcrumb", locale: locale) }
    expect(breadcrumbs).to be_present
    if path == root
      expect(breadcrumbs.text).to include(I18n.t("chrome.menu_bar.items.settings", locale: locale))
    else
      expect(breadcrumbs.css("a").map { |link| URI.parse(link["href"]).path }).to include(root)
    end

    navs = settings_navs(document, locale)
    expect(navs.size).to eq(3) # Desktop sidebar, global drawer, and settings dialog.
    navs.each do |nav|
      expect(nav.css('a[aria-current="page"]').map { |link| URI.parse(link["href"]).path }).to eq([active_path])
    end
    expect(document.css('[commandfor="settings-navigation-dialog"][command="show-modal"]').size).to eq(1)
    expect(document.css("#settings-navigation-dialog").size).to eq(1)
    expect(document.css(".translation_missing")).to be_empty
    document
  end

  it "opens the active section in the desktop sidebar and both mobile menus" do
    document = expect_shell(root, active_path: root, locale: :en)
    settings_navs(document, :en).each do |nav|
      details = nav.css('[data-list-filter-target="group"] details[data-list-filter-target="details"]')
      expect(details.size).to eq(destinations.keys.size)
      expect(details).to all(satisfy { |group| group["open"].nil? })
      expect(details.map { |group| label_text(group) }).to include(
        I18n.t("feature_modules.email.name"), I18n.t("feature_modules.authentication.name"),
        I18n.t("settings_navigation.groups.members"), I18n.t("settings_navigation.groups.billing")
      )
      expect(nav.at_css('a[href="' + root + '/modules/emails/template_tokens"]')).to be_present
    end

    document = expect_shell(root + "/modules/emails/template_tokens", active_path: root + "/modules/emails/template_tokens", locale: :en)
    settings_navs(document, :en).each do |nav|
      email_group = nav.css('details[data-list-filter-target="details"]').find do |group|
        group.at_css("summary").text.include?(I18n.t("feature_modules.email.name"))
      end
      expect(email_group["open"]).not_to be_nil
      expect(email_group.at_css('a[aria-current="page"]')).to be_present
      expect(nav.css('details[data-list-filter-target="details"][open]').size).to eq(1)
    end
  end

  it "keeps the collapsed rail as section controls without treating it as a fourth full task menu" do
    path = root + "/modules/sms/daily_cap"
    get path
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css('[data-sidebar-collapsible-target="rail"] nav').size).to eq(1)
    rail = document.at_css('[data-sidebar-collapsible-target="rail"] nav')
    expect(rail["aria-label"]).to eq(I18n.t("chrome.menu_bar.items.settings"))
    expect(settings_navs(document, :en).size).to eq(3)
    expect(rail.css('details[data-list-filter-target="details"]')).to be_empty
    sms = rail.css('button[data-action="click->sidebar-collapsible#expandGroup"]').find do |button|
      button["aria-label"] == I18n.t("feature_modules.sms.name")
    end
    expect(sms).to be_present
    expect(sms["class"]).to include("bg-accent-subtle")
    expect(rail.at_css('a[href="' + path + '"]')).to be_nil
    settings_navs(document, :en).each do |nav|
      expect(nav.css('a[aria-current="page"]').map { |link| URI.parse(link["href"]).path }).to eq([path])
    end
  end

  %w[en zh-CN].each do |locale|
    context "in #{locale}" do
      it "keeps the overview, catalog destinations, and all navigation menus grouped consistently" do
        document = expect_shell(root, active_path: root, locale: locale, title: I18n.t("chrome.menu_bar.items.settings", locale: locale))
        catalog = document.at_css("[data-settings-page] [data-settings-catalog]")
        expect(catalog).to be_present
        expect(catalog.css("section h2").map(&:text)).to eq(
          destinations.keys.map { |group| group_label(group, locale) }
        )
        expect(catalog.css("input[type='search'], [data-controller='list-filter']")).to be_empty
        [catalog, *settings_navs(document, locale)].each do |container|
          destinations.each do |group, items|
            heading = group_label(group, locale)
            section = group_nodes(container).find do |node|
               label_text(node) == heading
            end
            expect(section).to be_present
            expect(section.css("a").map { |link| URI.parse(link["href"]).path }).to eq(items.values.map { |suffix| root + suffix })
            items.each do |task, suffix|
              link = section.css("a").find { |node| URI.parse(node["href"]).path == root + suffix }
              label = I18n.t("settings_navigation.items.#{task}", locale: locale)
              expect(link.text).to include(label)
              expect(link.parent["data-search-text"]).to include(label) unless container == catalog
            end
          end
        end
      end

      %i[member_portal member_registration password_reset account_security roles_permissions user_access
         public_page_protection website ai_assistant email_sending_limit email_personalization
         sms_sending_limit payment_providers plan_subscription billing_payment_methods invoices].each do |task|
        it "renders #{task} with its task title and exactly one active destination per menu" do
          suffix = destinations.values.reduce({}, :merge).fetch(task)
          expect_shell(root + suffix, active_path: root + suffix, locale: locale,
                       title: I18n.t("settings_navigation.items.#{task}", locale: locale))
        end
      end

      it "retains the most specific navigation destination on deep settings pages" do
        role_id = customer.roles.find_by!(key: "admin").id
        {
          "/member/sources/builtin" => "/member",
          "/member/sources/modules" => "/member",
          "/member/sources/entities" => "/member",
          "/member/sources/builtin/surfaces/builtin_home" => "/member",
          "/member/sources/modules/surfaces/payments" => "/member",
          "/member/sources/entities/surfaces/entity_#{entity.id}" => "/member",
          "/modules/authentication/roles/new" => "/modules/authentication/roles",
          "/modules/authentication/roles/#{role_id}" => "/modules/authentication/roles",
          "/modules/authentication/roles/#{role_id}/grants" => "/modules/authentication/roles",
          "/modules/emails/template_tokens/new" => "/modules/emails/template_tokens",
          "/modules/emails/template_tokens/#{token.id}/edit" => "/modules/emails/template_tokens",
          "/modules/captcha/status" => "/modules/captcha",
          "/modules/payments/merchant_accounts/#{account.id}/edit" => "/modules/payments/merchant_accounts",
          "/billing/invoices/#{invoice.id}" => "/billing/invoices",
          "/billing/invoices/#{invoice.id}/download" => "/billing/invoices"
        }.each do |suffix, active|
          aggregate_failures(suffix) { expect_shell(root + suffix, active_path: root + active, locale: locale) }
        end
      end

      it "maps generic module aliases to exactly one canonical task in every navigation menu" do
        {
          "/modules/email" => "/modules/emails/daily_cap",
          "/modules/emails" => "/modules/emails/daily_cap",
          "/modules/sms" => "/modules/sms/daily_cap",
          "/modules/ai_assistants" => "/modules/ai_assistant",
          "/modules/authentications" => "/modules/authentication",
          "/modules/captcha/status" => "/modules/captcha"
        }.each do |suffix, canonical|
          aggregate_failures(suffix) { expect_shell(root + suffix, active_path: root + canonical, locale: locale) }
        end
      end
    end
  end

  it "removes unavailable modules from all menus and overview without exposing platform settings" do
    feature_module = FeatureModules::Module.find_by!(key: "payment")
    FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: feature_module).update!(status: :suspended)
    get root
    document = Nokogiri::HTML(response.body)
    [document.at_css("[data-settings-page]"), *settings_navs(document, :en)].each do |container|
      paths = container.css("a").map { |link| URI.parse(link["href"]).path }
      expect(paths).not_to include(root + "/modules/payments/merchant_accounts")
      expect(paths.grep(%r{/maintenance/platform/})).to be_empty
    end
    get root + "/modules/payments/merchant_accounts"
    expect(response).to have_http_status(:not_found)
  end

  %i[anonymous member other_admin].each do |actor|
    it "denies #{actor} access to every settings destination" do
      sign_out admin
      user = case actor
      when :member then create(:user, :member, customer: customer)
      when :other_admin then create(:user, :admin, customer: create(:customer))
      end
      sign_in user if user
      ["", *destinations.values.flat_map(&:values)].each do |suffix|
        get root + suffix
        expect(response).to have_http_status(:found), suffix
        expected_path = user ? Authentication::LandingPath.for(user) : new_user_session_path
        expect(URI.parse(response.location).path).to eq(expected_path), suffix
      end
    end
  end

  it "gives a future module its own settings section with a readable destination" do
    future = enable_module!("qa_tool", customer, name: "Team tools")
    future.update!(configuration_schema: { enabled: { type: "boolean", default: true } }.to_json)
    get root
    document = Nokogiri::HTML(response.body)
    [document.at_css("[data-settings-catalog]"), *settings_navs(document, :en)].each do |container|
      group = group_nodes(container).find do |node|
         label_text(node) == "Team tools"
      end
      link = group.at_css("a[href='#{root}/modules/qa_tools']")
      expect(link).to be_present
      expect(link.text).to include("Team tools")
    end
    expect_shell(root + "/modules/qa_tools", active_path: root + "/modules/qa_tools", locale: :en, title: "Team tools")
  end
end
