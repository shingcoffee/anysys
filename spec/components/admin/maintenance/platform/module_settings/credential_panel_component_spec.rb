# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleSettings::CredentialPanelComponent, type: :component do
  it "renders configured credentials with health-adjacent actions" do
    render_inline(described_class.new(
      title: "Sandbox",
      description: "Encrypted credentials",
      status: "Configured",
      status_variant: :success,
      action: '<a href="/edit">Edit credentials</a>'.html_safe,
      rows: [{ label: "Access key", value: "AK123" }]
    ))

    expect(page).to have_css("[data-credential-panel='true']")
    expect(page).to have_text("Configured")
    expect(page).to have_link("Edit credentials", href: "/edit")
    expect(page).to have_text("AK123")
  end

  it "renders incomplete, inactive, connection-failure, and create states" do
    %w[Incomplete Inactive Failed].each do |status|
      render_inline(described_class.new(title: "Provider", status: status, status_variant: :warning))
      expect(page).to have_text(status)
    end

    render_inline(described_class.new(
      title: "Production",
      description: "No credentials",
      action: '<a href="/new">Add credentials</a>'.html_safe
    ))
    expect(page).to have_link("Add credentials", href: "/new")
  end
end
