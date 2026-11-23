# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::ModuleCatalogCardComponent, type: :component do
  let(:customer_id) { 81_721_200 }
  let(:email) { build_stubbed(:feature_module, key: "email", name: "Email", required: false) }
  let(:auth) { build_stubbed(:feature_module, key: "authentication", name: "User Authentication", required: true) }
  let(:enablement_path) { "/81721200/admin/maintenance/modules/email/enablement" }

  def render_card(feature_module: email, enabled: true, **opts)
    render_inline(described_class.new(customer_id: customer_id, feature_module: feature_module, enabled: enabled, **opts))
  end

  it "shows the module identity, translated blurb and searchable text" do
    render_card

    expect(page).to have_css("h3", text: email.display_name)
    expect(page).to have_text(I18n.t("admin_misc.dashboard.modules.blurbs.email"))
    expect(page).to have_css("li[data-search-text*='#{email.display_name}']")
  end

  it "renders an enabled module as an on switch that DELETEs the enablement with confirmation" do
    render_card(enabled: true)

    expect(page).to have_css(".badge", text: I18n.t("common.status.enabled"))
    form = page.find("form[action='#{enablement_path}']")
    expect(form).to have_css("input[name='_method'][value='delete']", visible: :all)
    button = form.find("button[role='switch'][aria-checked='true']")
    expect(button["data-turbo-confirm"]).to eq(I18n.t("maint_core.modules.index.disable_confirm", name: email.display_name))
    expect(button["aria-label"]).to eq(I18n.t("maint_core.modules.index.toggle_aria", name: email.display_name))
  end

  it "renders a disabled module as an off switch that POSTs the enablement without confirmation" do
    render_card(enabled: false)

    expect(page).to have_css(".badge", text: I18n.t("common.status.disabled"))
    form = page.find("form[action='#{enablement_path}'][method='post']")
    expect(form).not_to have_css("input[name='_method']", visible: :all)
    expect(form.find("button[role='switch'][aria-checked='false']")["data-turbo-confirm"]).to be_nil
  end

  it "locks an enabled required module" do
    render_card(feature_module: auth, enabled: true)

    expect(page).to have_css(".badge", text: I18n.t("common.labels.required"))
    expect(page).to have_css("button[role='switch'][disabled][aria-checked='true']")
    expect(page).not_to have_css("form")
    expect(page).to have_text(I18n.t("maint_core.modules.index.locked_hint"))
  end

  it "lets an un-enabled required module be switched on" do
    render_card(feature_module: auth, enabled: false)

    expect(page).to have_css("form[method='post'] button[role='switch'][aria-checked='false']")
    expect(page).not_to have_text(I18n.t("maint_core.modules.index.locked_hint"))
  end

  it "links into the module only while it is enabled" do
    link = Dashboard::Link.new(label: "Templates", href: "/81721200/admin/modules/emails/templates")

    render_card(enabled: true, open_link: link)
    expect(page).to have_link(I18n.t("maint_core.modules.index.open_module"), href: link.href)

    render_card(enabled: false, open_link: link)
    expect(page).not_to have_link(I18n.t("maint_core.modules.index.open_module"))
  end
end
