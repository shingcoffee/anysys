# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ProviderStatusStripComponent, type: :component do
  it "renders health, role, and platform values with yielded actions" do
    render_inline(
      described_class.new(
        health_caption: "Connection",
        health_variant: :success,
        health_label: "Last check: OK",
        role_caption: "This provider",
        role_active: true,
        role_active_label: "Active for the platform",
        role_inactive_label: "Not the active provider",
        platform_caption: "Active provider",
        platform_value: "AWS Transcribe"
      )
    ) { "Test connection" }

    expect(page).to have_text("Connection")
    expect(page).to have_text("Last check: OK")
    expect(page).to have_text("Active for the platform")
    expect(page).to have_text("AWS Transcribe")
    expect(page).to have_text("Test connection")
  end
end
