# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Assistants::WorkspaceComponent, type: :component do
  let(:customer) { build_stubbed(:customer, id: 81_721_200, name: "Acme") }
  let(:user) { build_stubbed(:user, id: 1, customer: customer, first_name: "Jane", last_name: "Doe") }

  def render_workspace(assistant_available: false, messages: [], conversation: nil)
    with_request_url("/#{customer.id}/admin/assistant") do
      render_inline(
        described_class.new(
          customer: customer,
          user: user,
          assistant_available: assistant_available,
          assistant_messages: messages,
          assistant_conversation: conversation
        )
      )
    end
  end

  it "renders the offline empty state when the assistant is unavailable" do
    render_workspace
    expect(page).to have_text(I18n.t("ai_assistant.assistant.title"))
    expect(page).to have_text(I18n.t("ai_assistant.assistant.offline.body"))
    expect(page).to have_link(I18n.t("ai_assistant.assistant.offline.cta"), href: "/#{customer.id}/admin/maintenance/modules")
    expect(page).not_to have_css("[data-controller='ai-assistant']")
    expect(page).not_to have_css("[data-controller~='assistant-workspace']")
    expect(page).not_to have_css("[role='tablist']")
    expect(page).not_to have_css("[data-dashboard-region='overview']")
    expect(page).not_to have_text(I18n.t("admin_misc.dashboard.quick_actions"))
  end

  it "renders a responsive conversation and preview workspace" do
    render_workspace(assistant_available: true)

    expect(page).to have_css("[data-controller~='assistant-workspace']")
    expect(page).to have_css(
      "[role='tablist'][aria-label='#{I18n.t("ai_assistant.assistant.tabs.label")}']"
    )
    expect(page).to have_button(
      I18n.t("ai_assistant.assistant.tabs.conversation"),
      id: "assistant-conversation-tab"
    )
    expect(page).to have_button(
      I18n.t("ai_assistant.assistant.tabs.preview"),
      id: "assistant-preview-tab"
    )
    expect(page).to have_css("#assistant-preview-tab [data-assistant-workspace-target='artifactDot'].hidden", visible: :all)
    expect(page).to have_css(
      "#assistant-conversation-panel[role='tabpanel']" \
      "[data-assistant-workspace-id='conversation']" \
      "[aria-labelledby='assistant-conversation-tab']"
    )
    expect(page).to have_css(
      "#assistant-preview-panel[role='tabpanel']" \
      "[data-assistant-workspace-id='preview']" \
      "[aria-labelledby='assistant-preview-tab']"
    )
    expect(page).to have_css("[data-dashboard-region='overview']")
    expect(page).to have_css("[data-dashboard-region='chat']")
    expect(page).to have_css("##{AiAssistant::Stream::ARTIFACT_ID}")
    expect(page).to have_text(I18n.t("ai_assistant.assistant.artifact.empty"))
    expect(page).to have_css("[data-controller='ai-assistant']")
    expect(page).to have_css("textarea#ai_assistant_composer")
    html = rendered_content
    expect(html.index('data-dashboard-region="chat"')).to be < html.index('data-dashboard-region="overview"')
    expect(html).to include("lg:grid-cols-[minmax(0,1.45fr)_minmax(24rem,0.9fr)]")
    expect(html).to include("xl:grid-cols-[minmax(0,1.5fr)_minmax(26rem,0.85fr)]")
    # The chat switcher is a collapsed slide-over, so nothing holds a rail's
    # worth of width open beside the transcript.
    expect(html).not_to include("xl:w-64")
    expect(html).not_to include("xl:flex-row")
    expect(html).to include("data-ai-assistant-chats-host")
    expect(html).to include("-translate-x-full")
    expect(html).to include("px-3 py-2 lg:hidden")
    expect(html).not_to include("px-3 py-2.5")
    expect(page).to have_css("#assistant-conversation-panel[class*='lg:flex'][class*='lg:rounded-l-2xl']")
    # No literal `hidden` beside `flex`: the controller hides this below lg, and
    # a `display:block` pane loses flex-col and the artifact's h-full with it.
    expect(page).to have_css("#assistant-preview-panel.flex[class*='lg:flex'][class*='lg:rounded-r-2xl']")
    expect(page).not_to have_css("#assistant-preview-panel.hidden")
    expect(page).to have_css(
      "#assistant-conversation-panel" \
      "[data-assistant-workspace-role='tabpanel']" \
      "[data-assistant-workspace-labelled-by='assistant-conversation-tab']"
    )
    expect(page).to have_css(
      "#assistant-preview-panel" \
      "[data-assistant-workspace-role='tabpanel']" \
      "[data-assistant-workspace-labelled-by='assistant-preview-tab']"
    )
    expect(page).not_to have_text(I18n.t("ai_assistant.assistant.offline.body"))
    expect(page).not_to have_text(I18n.t("admin_misc.dashboard.setup.title"))
  end

  it "marks the Preview tab when the conversation has a resolved artifact" do
    customer = create(:customer)
    user = create(:user, customer: customer, first_name: "Jane", last_name: "Doe")
    conversation = create(:ai_assistant_conversation, customer: customer, user: user)
    entity = create(:entity, customer: customer)
    conversation.update!(artifact_kind: "entity", artifact_id: entity.id)

    with_request_url("/#{customer.id}/admin/assistant") do
      render_inline(
        described_class.new(
          customer: customer,
          user: user,
          assistant_available: true,
          assistant_conversation: conversation
        )
      )
    end

    dot = page.find("#assistant-preview-tab [data-assistant-workspace-target='artifactDot']")
    expect(dot[:class]).not_to include("hidden")
    # The mark itself is decorative, so the tab carries a text alternative too.
    expect(dot).to have_css("span[aria-hidden='true']")
    expect(dot).to have_css("span.sr-only", text: I18n.t("ai_assistant.assistant.tabs.preview_ready"), visible: :all)
    expect(page).to have_css("##{AiAssistant::Stream::ARTIFACT_ID}[data-artifact-present='true']")
  end

  it "does not mark the Preview tab when a conversation has no artifact" do
    customer = create(:customer)
    user = create(:user, customer: customer)
    conversation = create(:ai_assistant_conversation, customer: customer, user: user)

    with_request_url("/#{customer.id}/admin/assistant") do
      render_inline(
        described_class.new(
          customer: customer,
          user: user,
          assistant_available: true,
          assistant_conversation: conversation
        )
      )
    end

    expect(page).to have_css("#assistant-preview-tab [data-assistant-workspace-target='artifactDot'].hidden", visible: :all)
    expect(page).to have_css("##{AiAssistant::Stream::ARTIFACT_ID}[data-artifact-present='false']")
  end

  it "sets the document title" do
    component = described_class.new(
      customer: customer,
      user: user,
      assistant_available: true
    )
    context = vc_test_view_context

    with_request_url("/#{customer.id}/admin/assistant") do
      context.render(component)
    end

    expect(context.content_for(:title)).to eq(I18n.t("ai_assistant.assistant.title"))
  end
end
