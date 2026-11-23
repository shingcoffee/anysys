# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::ArtifactPreviewDialogComponent, type: :component do
  let(:name) { "Student form" }
  let(:preview_url) { "/81721200/admin/maintenance/pages/42/preview" }
  let(:details_url) { "/81721200/admin/maintenance/pages/42" }
  let(:frame_url) { "#{preview_url}?embed=1" }

  def render_dialog(**overrides)
    render_inline(
      described_class.new(
        name: name,
        preview_url: preview_url,
        details_url: details_url,
        details_label: I18n.t("ai_assistant.assistant.artifact.open_details"),
        subtitle: I18n.t("ai_assistant.assistant.artifact.current_saved"),
        **overrides
      )
    )
  end

  before { render_dialog }

  it "renders an accessible native dialog with a lazily loaded safe frame" do
    expect(page).to have_css(
      "dialog[aria-modal='true'][aria-labelledby='ai-assistant-artifact-preview-title']",
      visible: :all
    )
    expect(page).to have_css(
      "#ai-assistant-artifact-preview-title",
      text: I18n.t("ai_assistant.assistant.artifact.dialog_title", name: name),
      visible: :all
    )
    expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.current_saved"))
    expect(page).to have_button(
      I18n.t("ai_assistant.assistant.artifact.close_preview"),
      visible: :all
    )
    expect(page).to have_css(
      "button[aria-label='#{I18n.t("ai_assistant.assistant.artifact.close_preview")}']",
      visible: :all
    )

    frame = page.find("iframe[data-artifact-preview-target='frame']", visible: :all)
    expect(frame[:src]).to be_nil
    expect(frame[:"data-artifact-preview-src"]).to eq(preview_url)
    expect(frame[:sandbox]).to eq("allow-same-origin")
    expect(frame[:class]).to eq("h-full w-full border-0 bg-surface opacity-0")
    expect(frame[:class]).not_to include("pointer-events-none")
    expect(frame[:tabindex]).to be_blank
    expect(frame[:"aria-hidden"]).to be_blank
    frame_tag = rendered_content[%r{<iframe\b[^>]*\bdata-artifact-preview-target="frame"[^>]*>}]
    expect(frame_tag).to be_present
    expect(frame_tag).not_to include("pointer-events-none")
    expect(frame_tag).not_to include("tabindex")
    expect(frame_tag).not_to include("aria-hidden")
    expect(frame[:"data-action"]).to eq("load->artifact-preview#loaded error->artifact-preview#failed")
    expect(frame[:sandbox]).not_to include("allow-scripts")
    expect(frame[:sandbox]).not_to include("allow-forms")
  end

  it "keeps loading, failure, retry, and destination controls available" do
    expect(page).to have_css(
      "[data-artifact-preview-target='loading']",
      text: I18n.t("ai_assistant.assistant.artifact.preview_loading"),
      visible: :all
    )
    expect(page).to have_css(
      "[data-artifact-preview-target='failure']",
      text: I18n.t("ai_assistant.assistant.artifact.preview_unavailable"),
      visible: :all
    )
    expect(page).to have_button(
      I18n.t("ai_assistant.assistant.artifact.retry"),
      visible: :all
    )
    expect(page).to have_css(
      "a[href='#{preview_url}'][target='_blank'][rel='noopener noreferrer']",
      text: I18n.t("ai_assistant.assistant.artifact.open_preview"),
      visible: :all
    )
    expect(page).to have_css(
      "a[href='#{details_url}'][target='_blank'][rel='noopener noreferrer']",
      text: I18n.t("ai_assistant.assistant.artifact.open_details"),
      visible: :all
    )
    expect(page).to have_css(
      "footer a span.sr-only",
      text: I18n.t("ai_assistant.assistant.artifact.opens_new_tab"),
      count: 2,
      visible: :all
    )
  end

  it "falls back to preview_url for the frame when frame_url is omitted" do
    frame = page.find("iframe[data-artifact-preview-target='frame']", visible: :all)
    expect(frame[:"data-artifact-preview-src"]).to eq(preview_url)
    expect(page).to have_css(
      "a[href='#{preview_url}'][target='_blank'][rel='noopener noreferrer']",
      text: I18n.t("ai_assistant.assistant.artifact.open_preview"),
      visible: :all
    )
  end

  it "uses frame_url for the iframe while the footer preview link stays on preview_url" do
    render_dialog(frame_url: frame_url)

    frame = page.find("iframe[data-artifact-preview-target='frame']", visible: :all)
    expect(frame[:"data-artifact-preview-src"]).to eq(frame_url)
    expect(page).to have_css(
      "a[href='#{preview_url}'][target='_blank'][rel='noopener noreferrer']",
      text: I18n.t("ai_assistant.assistant.artifact.open_preview"),
      visible: :all
    )
    expect(page).not_to have_css(
      "a[href='#{frame_url}']",
      visible: :all
    )
  end

  it "labels the details link with details_label when one is given" do
    open_editor = I18n.t("ai_assistant.assistant.artifact.open_editor")
    render_dialog(details_label: open_editor)

    expect(page).to have_css(
      "a[href='#{details_url}'][target='_blank'][rel='noopener noreferrer']",
      text: open_editor,
      visible: :all
    )
    expect(page).not_to have_text(I18n.t("ai_assistant.assistant.artifact.open_details"))
  end

  it "shows the given subtitle instead of the saved-version note" do
    draft = I18n.t("ai_assistant.assistant.artifact.website_draft")
    render_dialog(subtitle: draft)

    expect(page).to have_text(draft)
    expect(page).not_to have_text(I18n.t("ai_assistant.assistant.artifact.current_saved"))
  end
end
