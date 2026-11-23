# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::DraftMessageComponent, type: :component do
  before { render_inline(described_class.new) }

  it "renders the draft broadcast target as its root" do
    expect(page).to have_css("##{AiAssistant::Stream::DRAFT_ID}[data-role='assistant-draft']")
  end

  it "renders the assistant author row without a timestamp or copy control" do
    expect(page).to have_text(I18n.t("ai_assistant.assistant.title"))
    expect(page).to have_css("##{AiAssistant::Stream::DRAFT_ID} > span[aria-hidden='true'] svg")
    expect(page).not_to have_css("time")
    expect(page).not_to have_css("button")
  end

  it "ships an empty progress slot for Turbo to fill" do
    slot = page.find("##{AiAssistant::Stream::DRAFT_STEPS_ID}")

    expect(slot.text).to eq("")
    expect(slot).not_to have_css("*")
  end

  it "ships an empty body slot with the assistant bubble typography" do
    body = page.find("##{AiAssistant::Stream::DRAFT_BODY_ID}")

    expect(body.text).to eq("")
    expect(body[:class]).to include("text-[15px]")
    expect(body[:class]).to include("leading-7")
    AiAssistant::MessageComponent::BUBBLE_MARKDOWN.split.each do |token|
      expect(body[:class]).to include(token)
    end
    expect(body[:class]).to include(AiAssistant::MessageComponent::DEFAULT_ASSISTANT_TONE)
  end

  # Stream.broadcast_delta rewrites this slot with the whole reply so far on
  # every frame, so a live region here would re-read the reply from the start
  # dozens of times over. The finished turn is announced once by the thread's
  # role="log", and ProgressComponent carries the in-flight signal.
  it "keeps the streaming body out of the accessibility tree's live regions" do
    body = page.find("##{AiAssistant::Stream::DRAFT_BODY_ID}")

    expect(body["role"]).to be_nil
    expect(body["aria-live"]).to be_nil
    expect(body["aria-label"]).to be_nil
  end

  it "renders a still-writing caret that respects reduced motion" do
    caret = page.find("span.animate-pulse")

    expect(caret[:class]).to include("motion-reduce:animate-none")
    expect(caret["aria-hidden"]).to eq("true")
  end

  it "labels itself in the current locale" do
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new)

      expect(page).to have_text(I18n.t("ai_assistant.assistant.title", locale: :"zh-CN"))
    end
  end
end
