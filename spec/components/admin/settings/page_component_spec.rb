# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Settings::PageComponent, type: :component do
  it "prepends the linked settings root, yields content, and renders one title" do
    rendered = render_inline(described_class.new(customer_id: 42, title: "Roles",
      breadcrumbs: [{ label: "People" }, { label: "Roles", path: "/roles" }])) { "Page content" }
    expect(rendered.css("nav a").map { |link| [link.text, link["href"]] }).to eq([
      ["Settings", "/42/admin/settings"]
    ])
    expect(rendered.css("nav span.text-text-primary").map(&:text)).to eq(["Roles"])
    expect(rendered.text).to include("People")
    expect(rendered.css("h1").map(&:text)).to eq(["Roles"])
    expect(rendered.css("[data-settings-page]").text).to include("Page content")
    expect(rendered.css("[role='alert']")).to be_empty
    expect(rendered.css("button[commandfor='settings-navigation-dialog'][command='show-modal']").text.strip).to eq("Settings menu")
  end

  it "forwards width, description, header actions and badges" do
    rendered = render_inline(described_class.new(customer_id: 42, title: "Provider", width: :standard,
      description: "Connection preferences", badges: [{ label: "Test", variant: :default }],
      actions: [{ label: "Save", form: "provider-form", variant: :primary }]))
    expect(rendered.text).to include("Connection preferences", "Test")
    expect(rendered.css("button[type='submit'][form='provider-form']").text).to include("Save")
  end

  it "sets the layout width through the shared page shell" do
    context = vc_test_view_context
    context.render(described_class.new(customer_id: 42, title: "Settings"))
    expect(context.content_for(:container_width)).to eq("full")
    context.render(described_class.new(customer_id: 42, title: "Settings", width: :standard))
    expect(context.content_for(:container_width)).to end_with("standard")
  end

  it "translates the settings breadcrumb and mobile trigger at render time" do
    component = described_class.new(customer_id: 42, title: "账户安全")
    I18n.with_locale(:"zh-CN") do
      render_inline(component)
      expect(page).to have_link("设置", href: "/42/admin/settings")
      expect(page).to have_button("设置菜单")
    end
  end

  it "publishes a print opt-in to the layout only when explicitly requested" do
    context = vc_test_view_context
    context.render(described_class.new(customer_id: 42, title: "Invoice"))
    expect(context.content_for(:settings_printable)).to be_nil

    context.render(described_class.new(customer_id: 42, title: "Invoice", printable: true))
    expect(context.content_for(:settings_printable)).to eq("true")
  end

  it "hides printable-page navigation and actions without hiding the yielded document" do
    actions = [{ label: "Back", path: "/invoices", class: "existing-action" }]
    rendered = render_inline(described_class.new(customer_id: 42, title: "Invoice", printable: true, actions: actions)) { "Full invoice" }
    expect(rendered.at_css("a[href='/invoices']")["class"]).to include("existing-action", "print:hidden")
    expect(rendered.at_css("button[command='show-modal']").parent["class"]).to include("print:hidden")
    expect(rendered.at_css("[data-settings-page]").text).to include("Full invoice")
    expect(rendered.at_css("[data-settings-page]").ancestors.none? { |node| node["class"].to_s.split.include?("print:hidden") }).to be(true)
    expect(actions.first[:class]).to eq("existing-action")
  end
end
