# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ProviderSwitcherComponent, type: :component do
  def render_switcher(items)
    render_inline(
      described_class.new(
        nav_label: "Providers",
        items: items
      )
    )
  end

  it "renders nothing when there are no providers" do
    render_switcher([])
    expect(page).not_to have_css("nav")
  end

  it "marks the current provider and badges the active one" do
    render_switcher([
      { name: "AWS Transcribe", path: "/stt?provider=aws_transcribe", current: true, active: true },
      { name: "OpenAI Whisper", path: "/stt?provider=openai_whisper", current: false, active: false }
    ])

    expect(page).to have_css("nav[aria-label='Providers']")
    expect(page).to have_css("a[aria-current='page']", text: "AWS Transcribe")
    expect(page).to have_text(I18n.t("common.status.active"))
    expect(page).to have_link("OpenAI Whisper", href: "/stt?provider=openai_whisper")
    expect(page).not_to have_css("a[aria-current='page']", text: "OpenAI Whisper")
  end
end
