# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleSettings::ProviderWorkspaceComponent, type: :component do
  it "renders the provider flow in the approved order" do
    render_inline(described_class.new) do |workspace|
      workspace.with_assignment { "Assignment" }
      workspace.with_provider { "Providers" }
      workspace.with_health { "Health" }
      workspace.with_credentials { "Credentials" }
      workspace.with_advanced_options { "Advanced" }
    end

    expect(page).to have_css("[data-provider-workspace='true']")
    %w[assignment provider health credentials advanced-options].each do |stage|
      expect(page).to have_css("[data-provider-workspace-section='#{stage}']")
    end
    html = page.native.to_html
    expect(html.index("Assignment")).to be < html.index("Providers")
    expect(html.index("Providers")).to be < html.index("Health")
    expect(html.index("Health")).to be < html.index("Credentials")
    expect(html.index("Credentials")).to be < html.index("Advanced")
  end

  it "omits stages without slot content instead of rendering empty markers" do
    render_inline(described_class.new) { |workspace| workspace.with_credentials { "Credentials" } }

    expect(page).to have_css("[data-provider-workspace-section='credentials']")
    expect(page).not_to have_css("[data-provider-workspace-section='health']")
    expect(page).not_to have_css("[data-provider-workspace-section='advanced-options']")
  end
end
