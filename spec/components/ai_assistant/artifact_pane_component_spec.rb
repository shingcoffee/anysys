# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::ArtifactPaneComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }

  def render_pane(viewer: nil)
    with_request_url("/#{customer.id}/admin/dashboard") do
      render_inline(described_class.new(conversation: conversation, customer: customer, viewer: viewer))
    end
  end

  it "renders the empty placeholder when nothing is pinned" do
    render_pane
    expect(page).to have_css("##{AiAssistant::Stream::ARTIFACT_ID}")
    expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.title"))
    expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.empty_title"))
    expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.empty"))
    kinds = page.find("[data-artifact-kinds]")
    expect(kinds).to have_text(I18n.t("ai_assistant.assistant.artifact.kinds.entity"))
    expect(kinds).to have_text(I18n.t("ai_assistant.assistant.artifact.kinds.page"))
    expect(kinds).not_to have_text(I18n.t("ai_assistant.assistant.artifact.kinds.flowchart"))
    expect(kinds).not_to have_css("button")
    expect(page).not_to have_css("ul li", text: I18n.t("ai_assistant.assistant.artifact.kinds.entity"))
    expect(page).not_to have_css("[data-controller~='artifact-preview']")
    expect(page).not_to have_css("dialog", visible: :all)
    expect(page).not_to have_link
  end

  it "lists flowchart as a preview kind for the platform owner" do
    render_pane(viewer: find_or_create_platform_owner)

    expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.empty_with_flowchart"))
    kinds = page.find("[data-artifact-kinds]")
    expect(kinds).to have_text(I18n.t("ai_assistant.assistant.artifact.kinds.flowchart"))
  end

  it "renders the safe empty state when an artifact no longer resolves" do
    conversation.update!(artifact_kind: "page", artifact_id: 999_999_999)
    render_pane

    expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.empty_title"))
    expect(page).to have_css("[data-artifact-kinds]", text: I18n.t("ai_assistant.assistant.artifact.kinds.entity"))
    expect(page).not_to have_css("iframe", visible: :all)
    expect(page).not_to have_link
  end

  it "renders an entity summary with an explicit details link" do
    entity = create(:entity, customer: customer, name: "Student")
    conversation.update!(artifact_kind: "entity", artifact_id: entity.id)
    render_pane

    expect(page).to have_text("Student")
    expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.kinds.entity"))
    expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.current_saved"))
    expect(page).to have_text(
      I18n.t(
        "ai_assistant.assistant.artifact.no_visual_preview",
        kind: I18n.t("ai_assistant.assistant.artifact.kinds.entity")
      )
    )
    expect(page).to have_css(
      "a[target='_blank'][rel='noopener noreferrer']",
      text: I18n.t("ai_assistant.assistant.artifact.open_details")
    )
    expect(page).to have_link(
      I18n.t("ai_assistant.assistant.artifact.open_details"),
      href: "/#{customer.id}/admin/maintenance/entities/#{entity.id}",
      count: 1
    )
    header = page.find("##{AiAssistant::Stream::ARTIFACT_ID} > header")
    expect(header).not_to have_link
    expect(header).to have_css("span.bg-border-strong[aria-hidden='true']")
    expect(page).not_to have_css("[data-controller~='artifact-preview']")
    expect(page).not_to have_css("iframe", visible: :all)
    expect(page).not_to have_css("dialog", visible: :all)
  end

  it "renders a flowchart summary without page preview controls for the platform owner" do
    conversation.update!(user: find_or_create_platform_owner)
    entity = create(:entity, customer: customer, name: "Student")
    flowchart = create(:flowchart, customer: customer, name: "Student intake")
    conversation.update!(artifact_kind: "flowchart", artifact_id: flowchart.id)
    render_pane

    expect(page).to have_text("Student intake")
    expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.kinds.flowchart"))
    expect(page).to have_text(
      I18n.t(
        "ai_assistant.assistant.artifact.no_visual_preview",
        kind: I18n.t("ai_assistant.assistant.artifact.kinds.flowchart")
      )
    )
    expect(page).to have_link(
      I18n.t("ai_assistant.assistant.artifact.open_details"),
      href: "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}"
    )
    expect(page).not_to have_button(I18n.t("ai_assistant.assistant.artifact.view_larger"))
    expect(page).not_to have_css("iframe", visible: :all)
    expect(page).not_to have_css("dialog", visible: :all)
  end

  it "hides a pinned flowchart from a tenant admin" do
    entity = create(:entity, customer: customer, name: "Student")
    flowchart = create(:flowchart, customer: customer, name: "Student intake")
    conversation.update!(artifact_kind: "flowchart", artifact_id: flowchart.id)
    render_pane

    expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.empty"))
    expect(page).not_to have_text("Student intake")
    expect(page).not_to have_link(href: "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}")
  end

  it "renders a secure page thumbnail, enlarged dialog, and separate destinations" do
    entity = create(:entity, customer: customer, name: "Student")
    page_record = create(:page, customer: customer, entity: entity, name: "Student form")
    conversation.update!(artifact_kind: "page", artifact_id: page_record.id)
    render_pane

    preview_path = "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/preview"
    embed_path = "#{preview_path}?embed=1"
    details_path = "/#{customer.id}/admin/maintenance/pages/#{page_record.id}"
    view_larger_label = I18n.t("ai_assistant.assistant.artifact.view_larger_label", name: page_record.name)

    expect(page).to have_css("[data-controller~='artifact-preview']")
    expect(page).to have_css("[data-artifact-preview-frame-width-value='960']")
    expect(page).to have_css("[data-artifact-preview-frame-height-value='1400']")
    expect(page).to have_css("[data-artifact-preview-target='viewport']")
    expect(page).to have_css("[data-artifact-preview-target='sheet']")
    expect(page).to have_css("[data-artifact-preview-target='canvas']")
    expect(page).to have_css("[data-artifact-preview-target='thumbnail']")
    viewport = page.find("[data-artifact-preview-target='viewport']")
    expect(viewport[:tabindex]).to eq("0")
    expect(viewport[:class]).to include("overflow-y-auto")
    expect(viewport[:"aria-describedby"]).to eq("ai-assistant-artifact-scroll-hint")
    expect(page).to have_css(
      "p#ai-assistant-artifact-scroll-hint",
      text: I18n.t("ai_assistant.assistant.artifact.scroll_hint")
    )
    expect(viewport[:"data-action"]).to include("scroll->artifact-preview#syncScroll")
    sheet = page.find("[data-artifact-preview-target='sheet']")
    expect(sheet[:style]).to include("height: 630px")
    # Clipping on the sheet would stop the stage from sticking.
    expect(sheet[:class]).not_to include("overflow")
    expect(page).to have_css(
      "[data-artifact-preview-target='sheet'] > [data-artifact-preview-target='stage'].sticky > " \
      "[data-artifact-preview-target='canvas'] > iframe[data-artifact-thumbnail]"
    )
    canvas = page.find("[data-artifact-preview-target='canvas']")
    expect(canvas[:style]).to eq("width: 960px; height: 1400px; transform: scale(0.45);")
    expect(page).to have_css(
      "button[data-artifact-preview-target='trigger'][data-action='artifact-preview#open'][aria-label='#{view_larger_label}']",
      count: 1
    )
    trigger = page.find("button[data-artifact-preview-target='trigger']")
    expect(trigger[:title]).to eq(I18n.t("ai_assistant.assistant.artifact.view_larger"))
    expect(page).to have_css("button[aria-label='#{view_larger_label}']", count: 1)
    expect(page).to have_css("button[data-action='artifact-preview#open']", count: 1)
    # The toolbar sits beside the scrolling viewport, so its links never
    # bubble into the viewport's click-to-enlarge.
    expect(page).not_to have_css("[data-artifact-preview-target='viewport'] a, [data-artifact-preview-target='viewport'] button")
    header = page.find("##{AiAssistant::Stream::ARTIFACT_ID} > header")
    expect(header).to have_link(I18n.t("ai_assistant.assistant.artifact.open_details"), href: details_path)
    expect(header).not_to have_link(href: preview_path)
    thumbnail = page.find("iframe[data-artifact-thumbnail]")
    expect(thumbnail[:src]).to eq(embed_path)
    expect(thumbnail[:"data-artifact-preview-target"]).to eq("thumbnail")
    expect(thumbnail[:"data-action"]).to eq("load->artifact-preview#thumbnailLoaded")
    expect(thumbnail[:sandbox]).to eq("allow-same-origin")
    expect(thumbnail[:tabindex]).to eq("-1")
    expect(thumbnail[:"aria-hidden"]).to eq("true")
    expect(thumbnail[:class]).to include("pointer-events-none")
    expect(thumbnail[:sandbox]).not_to include("allow-scripts")
    expect(thumbnail[:sandbox]).not_to include("allow-forms")

    expect(page).to have_css("dialog[aria-modal='true']", visible: :all)
    expect(page).to have_link(
      I18n.t("ai_assistant.assistant.artifact.open_preview"),
      href: preview_path,
      visible: :all
    )
    expect(page).to have_link(
      I18n.t("ai_assistant.assistant.artifact.open_details"),
      href: details_path,
      visible: :all
    )
    expect(page).to have_css(
      "a[target='_blank'][rel='noopener noreferrer']",
      count: 4,
      visible: :all
    )
  end

  describe "empty state copy" do
    it "mentions website pages when the Website module is enabled" do
      enable_module!("website", customer)
      render_pane

      expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.empty_with_website"))
      kinds = page.find("[data-artifact-kinds]")
      expect(kinds).to have_text(I18n.t("ai_assistant.assistant.artifact.kinds.website_page"))
      expect(kinds).not_to have_text(I18n.t("ai_assistant.assistant.artifact.kinds.flowchart"))
    end

    it "mentions flowcharts and website pages for the platform owner with the module enabled" do
      enable_module!("website", customer)
      render_pane(viewer: find_or_create_platform_owner)

      expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.empty_with_flowchart_and_website"))
      kinds = page.find("[data-artifact-kinds]")
      expect(kinds).to have_text(I18n.t("ai_assistant.assistant.artifact.kinds.flowchart"))
      expect(kinds).to have_text(I18n.t("ai_assistant.assistant.artifact.kinds.website_page"))
    end

    it "leaves website pages out while the Website module is off" do
      render_pane

      kinds = page.find("[data-artifact-kinds]")
      expect(kinds).not_to have_text(I18n.t("ai_assistant.assistant.artifact.kinds.website_page"))
    end
  end

  describe "a pinned website page" do
    let(:website) { create(:website, customer: customer) }
    let(:website_page) { create(:website_page, website: website, title: "Our menu") }
    let(:preview_path) { "/#{customer.id}/admin/modules/website/pages/#{website_page.id}/preview" }
    let(:edit_path) { "/#{customer.id}/admin/modules/website/pages/#{website_page.id}/edit" }

    before { conversation.update!(artifact_kind: "website_page", artifact_id: website_page.id) }

    it "frames the embedded draft preview and opens the Website editor" do
      enable_module!("website", customer)
      render_pane

      open_editor = I18n.t("ai_assistant.assistant.artifact.open_editor")
      expect(page).to have_css("[data-controller~='artifact-preview']")
      expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.kinds.website_page"))
      header = page.find("##{AiAssistant::Stream::ARTIFACT_ID} > header")
      expect(header).to have_text("Our menu")
      expect(header).to have_text(I18n.t("ai_assistant.assistant.artifact.website_draft"))
      expect(header).not_to have_text(I18n.t("ai_assistant.assistant.artifact.current_saved"))
      expect(header).to have_css("span.bg-warning[aria-hidden='true']")

      thumbnail = page.find("iframe[data-artifact-thumbnail]")
      expect(thumbnail[:src]).to eq("#{preview_path}?embed=1")
      expect(thumbnail[:sandbox]).to eq("allow-same-origin")
      dialog_frame = page.find("iframe[data-artifact-preview-target='frame']", visible: :all)
      expect(dialog_frame[:"data-artifact-preview-src"]).to eq("#{preview_path}?embed=1")
      expect(page).not_to have_text(:all, I18n.t("ai_assistant.assistant.artifact.current_saved"))

      expect(page).to have_link(I18n.t("ai_assistant.assistant.artifact.open_preview"), href: preview_path)
      expect(page).to have_link(open_editor, href: edit_path)
      expect(page).to have_link(open_editor, href: edit_path, visible: :all, count: 2)
      expect(page).not_to have_text(I18n.t("ai_assistant.assistant.artifact.open_details"))
      expect(page).to have_css(
        "a[target='_blank'][rel='noopener noreferrer']",
        count: 4,
        visible: :all
      )
    end

    it "labels a published website page as published" do
      enable_module!("website", customer)
      website_page.update!(published: true)
      render_pane

      header = page.find("##{AiAssistant::Stream::ARTIFACT_ID} > header")
      expect(header).to have_text(I18n.t("ai_assistant.assistant.artifact.website_published"))
      expect(header).not_to have_text(I18n.t("ai_assistant.assistant.artifact.website_draft"))
      expect(header).to have_css("span.bg-success[aria-hidden='true']")
      expect(header).not_to have_css("span.bg-warning")
    end

    it "shows nothing pinned once the Website module is disabled" do
      render_pane

      expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.empty_title"))
      expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.empty"))
      expect(page).not_to have_text("Our menu")
      expect(page).not_to have_css("iframe", visible: :all)
      expect(page).not_to have_link
    end
  end
end
