# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::ProgressComponent, type: :component do
  def step(key, state, detail: nil)
    AiAssistant::Assistant::Progress::Step.new(key: key, state: state, detail: detail)
  end

  it "renders nothing when there are no steps" do
    render_inline(described_class.new(steps: []))

    expect(rendered_content.strip).to eq("")
    expect(page).not_to have_css("##{AiAssistant::Stream::DRAFT_STEPS_ID}")
  end

  it "renders the broadcast target as its root, announced politely" do
    render_inline(described_class.new(steps: [ step(:thinking, :running) ]))

    root = page.find("##{AiAssistant::Stream::DRAFT_STEPS_ID}")
    expect(root["role"]).to eq("status")
    expect(root["aria-live"]).to eq("polite")
    expect(root["aria-label"]).to eq(I18n.t("ai_assistant.assistant.progress.label"))
    expect(page).to have_css("ol li", count: 1)
  end

  it "renders an ordered trace with one row per step" do
    render_inline(
      described_class.new(
        steps: [
          step(:catalog, :done),
          step(:entity, :running),
          step(:verify, :failed)
        ]
      )
    )

    rows = page.all("ol > li")
    expect(rows.map { |row| row["data-progress-step"] }).to eq(%w[catalog entity verify])
    expect(rows.map { |row| row["data-state"] }).to eq(%w[done running failed])
  end

  it "marks a running step with a pulsing dot that respects reduced motion" do
    render_inline(described_class.new(steps: [ step(:thinking, :running) ]))

    dot = page.find("[data-state='running'] span[aria-hidden='true']")
    expect(dot[:class]).to include("animate-pulse")
    expect(dot[:class]).to include("motion-reduce:animate-none")
    expect(page).not_to have_css("[data-state='running'] svg")
  end

  it "marks a done step with a muted check and a failed step with a danger cross" do
    render_inline(described_class.new(steps: [ step(:catalog, :done), step(:repair, :failed) ]))

    expect(page).to have_css("[data-state='done'] svg.text-text-muted")
    expect(page).to have_css("[data-state='failed'] svg.text-danger")
    expect(page).to have_css("[data-state='failed'] span.text-danger")
    expect(page).not_to have_css("[data-state='done'] .animate-pulse")
  end


  it "renders every step label from the current locale" do
    steps = AiAssistant::Assistant::Progress::KEYS.map { |key| step(key, :done) }

    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(steps: steps))

      AiAssistant::Assistant::Progress::KEYS.each do |key|
        expect(page).to have_text(I18n.t("ai_assistant.assistant.progress.#{key}", locale: :"zh-CN"))
      end
      expect(page.find("##{AiAssistant::Stream::DRAFT_STEPS_ID}")["aria-label"])
        .to eq(I18n.t("ai_assistant.assistant.progress.label", locale: :"zh-CN"))
    end
  end

  it "appends a server-supplied detail next to the label" do
    render_inline(described_class.new(steps: [ step(:entity, :running, detail: "Student") ]))

    expect(page).to have_text(I18n.t("ai_assistant.assistant.progress.entity"))
    expect(page).to have_text("Student")
  end

  it "stays at caption weight so it does not out-shout the reply" do
    render_inline(described_class.new(steps: [ step(:thinking, :running) ]))

    expect(page).to have_css("li.text-caption")
    expect(page).not_to have_css(".text-text-primary")
  end
end
