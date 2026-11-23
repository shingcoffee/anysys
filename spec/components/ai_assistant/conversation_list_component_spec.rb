# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::ConversationListComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, customer: customer) }

  def render_list(current_id: nil)
    with_request_url("/#{customer.id}/admin/dashboard") do
      render_inline(described_class.new(customer: customer, user: user, current_id: current_id))
    end
  end

  def chat(title:, archived: false, last_active_at: Time.current)
    conversation = create(:ai_assistant_conversation, customer: customer, user: user, title: title)
    conversation.update_columns(
      last_active_at: last_active_at,
      archived_at: archived ? Time.current : nil
    )
    conversation.reload
  end

  def send_in!(conversation)
    create(:ai_assistant_message, customer: customer, conversation: conversation)
    conversation
  end

  def new_chat_button
    page.find("button[data-action='ai-assistant-conversations#create']", visible: :all)
  end

  it "renders the broadcast target and the new-chat action" do
    render_list

    expect(page).to have_css("##{AiAssistant::Stream::CONVERSATIONS_ID}[data-controller='ai-assistant-conversations']")
    expect(page).to have_text(I18n.t("ai_assistant.assistant.conversations.title"))
    heading = page.find("h2.sr-only", text: I18n.t("ai_assistant.assistant.conversations.title"), visible: :all)
    expect(heading[:class]).not_to include("xl:not-sr-only")
    expect(page).to have_css("##{described_class::HEADING_ID}", text: I18n.t("ai_assistant.assistant.conversations.title"), visible: :all)
    expect(page).to have_css(
      "button.btn-secondary[data-action='ai-assistant-conversations#create']",
      text: I18n.t("ai_assistant.assistant.conversations.new")
    )
    expect(page).not_to have_css("button.btn-primary[data-action='ai-assistant-conversations#create']")
  end

  it "renders the empty state when the user has no chats" do
    render_list

    expect(page).to have_text(I18n.t("ai_assistant.assistant.conversations.empty"))
    expect(page).not_to have_css("li[data-conversation-id]")
    expect(page).not_to have_css("details summary", text: I18n.t("ai_assistant.assistant.conversations.archived_section"))
  end

  it "lists active chats most recently active first" do
    chat(title: "Older", last_active_at: 2.days.ago)
    chat(title: "Newer", last_active_at: 1.minute.ago)

    render_list

    titles = page.all("##{AiAssistant::ConversationListComponent::PANEL_ID} ul li a span.truncate").map(&:text)
    expect(titles).to eq(%w[Newer Older])
  end

  it "links each row to the conversation on the assistant path and shows a relative timestamp" do
    conversation = chat(title: "Budgeting", last_active_at: 3.hours.ago)

    render_list

    link = page.find("li[data-conversation-id='#{conversation.id}'] a")
    expect(link[:href]).to eq("/#{customer.id}/admin/assistant?conversation=#{conversation.id}")
    expect(link).to have_css("time[datetime='#{conversation.last_active_at.iso8601}']")
    expect(link).to have_text(
      I18n.t("chrome.admin_table.time_ago", time: ActionController::Base.helpers.time_ago_in_words(conversation.last_active_at))
    )
  end

  it "falls back to the untitled label for a chat with no title" do
    conversation = create(:ai_assistant_conversation, customer: customer, user: user, title: nil)

    render_list


    expect(page).to have_css(
      "li[data-conversation-id='#{conversation.id}']",
      text: I18n.t("ai_assistant.assistant.conversations.untitled")
    )
  end

  it "marks the current chat visually and for assistive tech" do
    current = chat(title: "Current", last_active_at: 1.minute.ago)
    other = chat(title: "Other", last_active_at: 2.days.ago)

    render_list(current_id: current.id)

    current_link = page.find("li[data-conversation-id='#{current.id}'] a")
    expect(current_link["aria-current"]).to eq("page")
    expect(current_link[:class]).to include("bg-accent-subtle")
    expect(current_link).to have_css("span.sr-only", text: I18n.t("ai_assistant.assistant.conversations.current"), visible: :all)

    other_link = page.find("li[data-conversation-id='#{other.id}'] a")
    expect(other_link["aria-current"]).to be_nil
    expect(other_link[:class]).not_to include("bg-accent-subtle")
    expect(page).to have_css(
      "p.truncate[title='Current']",
      text: "Current"
    )
  end

  it "accepts a string current_id from the query string" do
    current = chat(title: "Current")

    render_list(current_id: current.id.to_s)

    expect(page.find("li[data-conversation-id='#{current.id}'] a")["aria-current"]).to eq("page")
  end

  it "renders a per-row actions menu wired to the Stimulus contract" do
    conversation = chat(title: "Budgeting")

    render_list

    row = page.find("li[data-conversation-id='#{conversation.id}']")
    expect(row.find("details summary")["aria-label"]).to eq(I18n.t("ai_assistant.assistant.conversations.actions"))

    rename = row.find("[data-action='ai-assistant-conversations#rename']", visible: :all)
    expect(rename["data-ai-assistant-conversations-url-param"]).to eq("/#{customer.id}/admin/modules/ai_assistant/conversations/#{conversation.id}")
    expect(rename["data-ai-assistant-conversations-id-param"]).to eq(conversation.id.to_s)
    expect(rename["data-ai-assistant-conversations-title-param"]).to eq("Budgeting")
    expect(rename.text.strip).to eq(I18n.t("ai_assistant.assistant.conversations.rename"))

    archive = row.find("[data-action='ai-assistant-conversations#archive']", visible: :all)
    expect(archive["data-ai-assistant-conversations-url-param"]).to eq("/#{customer.id}/admin/modules/ai_assistant/conversations/#{conversation.id}/archive")
    expect(archive["data-ai-assistant-conversations-archived-param"]).to eq("false")
    expect(archive.text.strip).to eq(I18n.t("ai_assistant.assistant.conversations.archive"))

    destroy = row.find("[data-action='ai-assistant-conversations#destroy']", visible: :all)
    expect(destroy["data-ai-assistant-conversations-url-param"]).to eq("/#{customer.id}/admin/modules/ai_assistant/conversations/#{conversation.id}")
    expect(destroy.text.strip).to eq(I18n.t("ai_assistant.assistant.conversations.delete"))
  end

  it "exposes the urls and translated labels the Stimulus controller needs" do
    render_list

    root = page.find("##{AiAssistant::Stream::CONVERSATIONS_ID}")
    collection = "/#{customer.id}/admin/modules/ai_assistant/conversations"

    expect(root["data-ai-assistant-conversations-create-url-value"]).to eq(collection)
    expect(root["data-ai-assistant-conversations-base-url-value"]).to eq(collection)
    expect(root["data-ai-assistant-conversations-panel-id-value"]).to eq(described_class::PANEL_ID)
    # The delete copy lives in the dialog now, so it no longer travels as a value.
    expect(root["data-ai-assistant-conversations-delete-confirm-value"]).to be_nil
    expect(root["data-ai-assistant-conversations-rename-label-value"]).to eq(I18n.t("ai_assistant.assistant.conversations.rename_label"))
    expect(root["data-ai-assistant-conversations-save-label-value"]).to eq(I18n.t("ai_assistant.assistant.conversations.save"))
    expect(root["data-ai-assistant-conversations-cancel-label-value"]).to eq(I18n.t("ai_assistant.assistant.conversations.cancel"))
    expect(root["data-ai-assistant-conversations-failed-label-value"]).to eq(I18n.t("ai_assistant.assistant.conversations.failed"))
  end

  # Deleting takes the whole transcript with it, so it is asked in a dialog that
  # names the action rather than in an unstyled native prompt.
  it "ships a confirmation dialog that opens on Cancel and names the destructive action" do
    render_list

    dialog = page.find("##{described_class::DELETE_DIALOG_ID}", visible: :all)
    expect(dialog.tag_name).to eq("dialog")
    expect(dialog["aria-modal"]).to eq("true")
    expect(dialog["aria-labelledby"]).to eq(described_class.new(customer: customer, user: user).delete_dialog_title_id)
    expect(dialog["aria-describedby"]).to eq(described_class.new(customer: customer, user: user).delete_dialog_body_id)
    expect(dialog["data-ai-assistant-conversations-target"]).to eq("deleteDialog")
    expect(dialog["data-action"]).to eq("cancel->ai-assistant-conversations#cancelDestroy")
    expect(dialog).to have_text(I18n.t("ai_assistant.assistant.conversations.delete_title"))
    expect(dialog).to have_text(I18n.t("ai_assistant.assistant.conversations.delete_confirm"))

    cancel = dialog.find("[data-action='click->ai-assistant-conversations#cancelDestroy']", visible: :all)
    expect(cancel.text.strip).to eq(I18n.t("ai_assistant.assistant.conversations.cancel"))
    expect(cancel["autofocus"]).to be_truthy

    confirm = dialog.find("[data-action='click->ai-assistant-conversations#confirmDestroy']", visible: :all)
    expect(confirm.text.strip).to eq(I18n.t("ai_assistant.assistant.conversations.delete_action"))
    expect(confirm[:class]).to include("btn-danger")
  end

  # The broadcast replaces this whole element, so a slot the controller builds
  # on demand is thrown away with it.
  it "renders the error slot rather than leaving the controller to build one" do
    render_list

    alert = page.find("##{described_class::ALERT_ID}", visible: :all)
    expect(alert["role"]).to eq("alert")
    expect(alert["aria-live"]).to eq("assertive")
    expect(alert["data-ai-assistant-conversations-target"]).to eq("alert")
    expect(alert[:class]).to include("hidden")
    expect(alert.text).to eq("")
  end

  # The composer is not inside this element, so its "Start a new chat" control
  # has to reach the list as an event.
  it "accepts a new-chat request from outside the list" do
    render_list

    expect(page.find("##{AiAssistant::Stream::CONVERSATIONS_ID}")["data-action"])
      .to eq("ai-assistant:newChat@window->ai-assistant-conversations#create")
  end

  it "collapses archived chats into their own disclosure with an unarchive action" do
    active = chat(title: "Active")
    archived = chat(title: "Filed away", archived: true)

    render_list

    expect(page).to have_css("details summary", text: I18n.t("ai_assistant.assistant.conversations.archived_section"))
    expect(page).to have_css("##{described_class::PANEL_ID} > div > ul li[data-conversation-id='#{active.id}']")
    expect(page).to have_css("details > ul li[data-conversation-id='#{archived.id}']", visible: :all)

    unarchive = page.find("li[data-conversation-id='#{archived.id}'] [data-action='ai-assistant-conversations#archive']", visible: :all)
    expect(unarchive.text.strip).to eq(I18n.t("ai_assistant.assistant.conversations.unarchive"))
    expect(unarchive["data-ai-assistant-conversations-archived-param"]).to eq("true")
  end

  it "caps the archived disclosure" do
    stub_const("#{described_class}::ARCHIVED_LIMIT", 2)
    3.times { |i| chat(title: "Filed #{i}", archived: true, last_active_at: i.minutes.ago) }

    render_list

    expect(page).to have_css("details > ul li[data-conversation-id]", count: 2, visible: :all)
    expect(page).to have_text("Filed 0", normalize_ws: true)
    expect(page).not_to have_text("Filed 2")
  end

  it "never shows another user's or another tenant's chats" do
    mine = chat(title: "Mine")
    other_user = create(:user, customer: customer)
    create(:ai_assistant_conversation, customer: customer, user: other_user, title: "Theirs")
    other_customer = create(:customer)
    create(
      :ai_assistant_conversation,
      customer: other_customer,
      user: create(:user, customer: other_customer),
      title: "Other tenant"
    )

    render_list

    expect(page).to have_css("li[data-conversation-id='#{mine.id}']")
    expect(page).to have_css("li[data-conversation-id]", count: 1)
    expect(page).not_to have_text("Theirs")
    expect(page).not_to have_text("Other tenant")
  end

  # The transcript is the reason the page exists, so the switcher starts
  # as a left slide-over collapsed off-canvas at every width.
  it "is a left slide-over that starts collapsed at every width" do
    render_list

    toggle = page.find("##{described_class::TOGGLE_ID}")
    expect(toggle[:class]).not_to include("xl:hidden")
    expect(toggle[:class]).to include("group")
    expect(toggle[:class]).to include("shrink-0")
    expect(toggle[:class]).not_to include("flex-1")
    expect(toggle["aria-expanded"]).to eq("false")
    expect(toggle["aria-controls"]).to eq(described_class::PANEL_ID)
    expect(toggle["data-ai-assistant-conversations-target"]).to eq("toggle")
    expect(toggle["data-action"]).to eq("ai-assistant-conversations#toggle")
    expect(toggle).to have_text(I18n.t("ai_assistant.assistant.conversations.toggle"))
    hide = toggle.find("span", text: I18n.t("ai_assistant.assistant.conversations.toggle_hide"), visible: :all)
    expect(hide[:class]).to include("hidden")
    expect(hide[:class]).to include("group-aria-expanded:inline")

    panel = page.find("##{described_class::PANEL_ID}", visible: :all)
    expect(panel[:class]).to include("-translate-x-full")
    expect(panel[:class]).not_to include("xl:flex")
    expect(panel[:class]).not_to include("max-h-52")
    expect(panel[:class]).not_to include("xl:max-h-none")
    expect(panel["data-ai-assistant-conversations-target"]).to eq("panel")
    expect(panel["role"]).to eq("dialog")
    expect(panel["aria-hidden"]).to eq("true")
    expect(page).to have_css("[data-ai-assistant-conversations-target='backdrop']", visible: :all)
    expect(page).to have_css(
      "button[data-action='ai-assistant-conversations#close'][aria-label='#{I18n.t("ai_assistant.assistant.conversations.close")}']",
      visible: :all
    )
  end

  # Starting a chat from an unused one would only produce two identical blank
  # rows, so the control is closed off until the open thread has been used.
  describe "starting a new chat while the open one is still empty" do
    it "disables the control and says why" do
      open_chat = chat(title: "Fresh")

      render_list(current_id: open_chat.id)

      expect(new_chat_button[:disabled]).to eq("true").or eq("disabled")
      expect(new_chat_button[:title]).to eq(I18n.t("ai_assistant.errors.current_chat_empty"))
      expect(new_chat_button[:"aria-describedby"]).to eq(described_class::NEW_HINT_ID)
      expect(page).to have_css(
        "##{described_class::NEW_HINT_ID}.sr-only",
        text: I18n.t("ai_assistant.errors.current_chat_empty"),
        visible: :all
      )
      expect(page).not_to have_css("##{described_class::NEW_HINT_ID}.text-caption")
    end

    it "enables it again once that chat has a message" do
      open_chat = send_in!(chat(title: "Used"))

      render_list(current_id: open_chat.id)

      expect(new_chat_button[:disabled]).to be_nil
      expect(page).not_to have_text(I18n.t("ai_assistant.errors.current_chat_empty"))
    end

    it "judges the most recent chat when the list is rendered without a current id" do
      chat(title: "Empty and newest", last_active_at: Time.current)
      send_in!(chat(title: "Used and older", last_active_at: 1.day.ago))

      render_list

      expect(new_chat_button[:disabled]).to eq("true").or eq("disabled")
    end

    it "stays enabled for a user with no chats at all" do
      render_list

      expect(new_chat_button[:disabled]).to be_nil
    end

    it "ignores an empty chat that has been archived" do
      chat(title: "Archived empty", archived: true)
      send_in!(chat(title: "Active and used"))

      render_list

      expect(new_chat_button[:disabled]).to be_nil
    end
  end

  it "gives rows and row controls a coarse-pointer touch target" do
    chat(title: "Budgeting")

    render_list

    expect(page.find("li[data-conversation-id] a")[:class]).to include("pointer-coarse:min-h-11")
    expect(page.find("li[data-conversation-id]")[:class]).to include("group/chat")
    kebab = page.find("li[data-conversation-id] details summary")
    expect(kebab[:class]).to include("pointer-coarse:size-11")
    expect(kebab[:class]).to include("pointer-fine:opacity-0")
    expect(kebab[:class]).to include("pointer-fine:group-hover/chat:opacity-100")
    expect(page.find("##{described_class::TOGGLE_ID}")[:class]).to include("pointer-coarse:min-h-11")
  end

  it "renders in the reader's locale" do
    chat(title: "Budgeting", archived: true)

    I18n.with_locale(:"zh-CN") do
      render_list

      expect(page).to have_text(I18n.t("ai_assistant.assistant.conversations.title", locale: :"zh-CN"))
      expect(page).to have_text(I18n.t("ai_assistant.assistant.conversations.new", locale: :"zh-CN"))
      expect(page).to have_css(
        "span",
        text: I18n.t("ai_assistant.assistant.conversations.toggle_hide", locale: :"zh-CN"),
        visible: :all
      )
      expect(page).to have_css(
        "button[aria-label='#{I18n.t("ai_assistant.assistant.conversations.close", locale: :"zh-CN")}']",
        visible: :all
      )
      expect(page).to have_text(I18n.t("ai_assistant.assistant.conversations.archived_section", locale: :"zh-CN"))
      expect(page).to have_css(
        "##{described_class::DELETE_DIALOG_ID}",
        text: I18n.t("ai_assistant.assistant.conversations.delete_confirm", locale: :"zh-CN"),
        visible: :all
      )
      expect(page).to have_css(
        "##{described_class::DELETE_DIALOG_ID} button",
        text: I18n.t("ai_assistant.assistant.conversations.delete_action", locale: :"zh-CN"),
        visible: :all
      )
    end
  end
end
