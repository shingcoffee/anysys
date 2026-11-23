# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::AssistantPanelComponent, type: :component do
  let(:customer_id) { 81_721_200 }
  let(:user_id) { 1 }
  let(:conversation_id) { 42 }

  def render_panel(messages: [], viewer: nil)
    with_request_url("/#{customer_id}/admin/dashboard") do
      render_inline(
        described_class.new(
          messages: messages,
          customer_id: customer_id,
          user_id: user_id,
          user_name: "Ada",
          conversation_id: conversation_id,
          viewer: viewer
        )
      )
    end
  end

  it "renders the greeting empty state and composer" do
    render_panel
    expect(page).to have_css("h2#ai-assistant-title", text: I18n.t("ai_assistant.assistant.title"), visible: :all)
    expect(page).not_to have_text(I18n.t("ai_assistant.assistant.subtitle"))
    expect(page).not_to have_text(I18n.t("ai_assistant.assistant.what"))
    expect(page).to have_text(I18n.t("ai_assistant.assistant.how"))
    expect(page).to have_text(I18n.t("ai_assistant.assistant.try"))
    expect(page).to have_text(I18n.t("ai_assistant.assistant.greeting", name: "Ada"))
    expect(page).to have_css("##{AiAssistant::Stream::EMPTY_ID}")
    expect(page).to have_css("textarea#ai_assistant_composer[data-speech-to-text-target='field'][data-ai-assistant-target='composer']")
    expect(page).to have_css("textarea#ai_assistant_composer[aria-describedby='#{described_class::HINT_ID} #{described_class::ERROR_ID}']")
    expect(page).to have_css(
      "p##{described_class::HINT_ID}",
      text: I18n.t("ai_assistant.assistant.composer_hint")
    )
    expect(page).to have_css("[data-ai-assistant-copy-label-value='#{I18n.t("ai_assistant.assistant.copy")}']")
    expect(page).to have_css("[data-ai-assistant-copied-label-value='#{I18n.t("ai_assistant.assistant.copied")}']")
    expect(page).to have_css("[data-ai-assistant-copy-failed-label-value='#{I18n.t("ai_assistant.assistant.copy_failed")}']")
    expect(page).to have_css("[data-ai-assistant-send-failed-label-value='#{I18n.t("ai_assistant.assistant.send_failed")}']")
    expect(page).to have_css("[data-ai-assistant-stop-url-value='/#{customer_id}/admin/modules/ai_assistant/messages/stop']")
    expect(page).not_to have_css("button[aria-label='#{I18n.t("ai_assistant.assistant.copy")}']")
    expect(page).to have_css("button[aria-label='#{I18n.t("ai_assistant.assistant.attach")}']")
    expect(page).to have_css("input[type='file']")
    expect(page).to have_css("button[aria-label='#{I18n.t("ai_assistant.assistant.stop")}']")
    expect(page).to have_css("##{AiAssistant::Stream::STATUS_ID}[role='status'][aria-live='polite']")
    expect(page).to have_css("##{AiAssistant::Stream::RUNNING_ID}", visible: :hidden)
    expect(rendered_content).to include("/#{customer_id}/admin/modules/ai_assistant/messages/stop")
    %w[create_entity new_page enable_module].each do |key|
      prompt = I18n.t("ai_assistant.assistant.prompts.#{key}")
      label = I18n.t("ai_assistant.assistant.prompt_labels.#{key}")
      expect(page).to have_css("button[data-prompt='#{prompt}']", text: label)
      expect(page).to have_css("button[data-prompt='#{prompt}']", text: prompt)
    end
    expect(page).to have_css(".flex-1.flex-col")
    html = rendered_content
    expect(html).to include("text-xl font-semibold")
    expect(html).not_to include("text-3xl")
    expect(html).not_to include("self-start")
    expect(html).to include("border-t border-border-subtle bg-canvas")
    expect(html).to include("flex-col gap-4")
    expect(html).to include("shadow-float")
    expect(html).not_to include("max-w-sm overflow-hidden")
    expect(page).not_to have_css(
      "button[data-prompt='#{I18n.t("ai_assistant.assistant.prompts.create_flowchart")}']"
    )
  end

  it "passes the attachment limits, including the per-message total, to the composer" do
    render_panel
    rules = AiAssistant::Assistant::Attachments
    expect(page).to have_css("[data-ai-assistant-max-files-value='#{rules::MAX_FILES}']")
    expect(page).to have_css("[data-ai-assistant-max-total-bytes-value='#{rules::MAX_TOTAL_BYTES}']")
    expect(page).to have_css("[data-ai-assistant-total-size-label-value='#{I18n.t("ai_assistant.errors.images_too_large_total")}']")
  end

  it "passes its selected conversation into the assistant dictation upload widget" do
    allow_any_instance_of(SpeechToText::DictateFieldComponent).to receive(:show_widget?).and_return(true)
    render_panel
    expect(page).to have_css("[data-speech-to-text-conversation-id-value='#{conversation_id}'][data-speech-to-text-destination-value='assistant']")
  end

  it "offers the flowchart starter prompt to the platform owner" do
    render_panel(viewer: find_or_create_platform_owner)
    prompt = I18n.t("ai_assistant.assistant.prompts.create_flowchart")
    label = I18n.t("ai_assistant.assistant.prompt_labels.create_flowchart")
    expect(page).to have_css("button[data-prompt='#{prompt}']", text: label)
  end

  describe "the website starter prompt" do
    let(:customer) { create(:customer) }
    let(:customer_id) { customer.id }
    let(:website_prompt) { I18n.t("ai_assistant.assistant.prompts.create_website") }

    def card_keys(viewer: nil)
      described_class.new(
        messages: [],
        customer_id: customer_id,
        user_id: user_id,
        user_name: "Ada",
        conversation_id: conversation_id,
        viewer: viewer
      ).prompt_cards.map(&:key)
    end

    it "is hidden while the Website module is off" do
      render_panel

      expect(page).not_to have_css(%(button[data-prompt="#{website_prompt}"]))
      expect(card_keys).to eq(%w[create_entity new_page enable_module])
    end

    it "follows the entity prompt when the Website module is enabled" do
      enable_module!("website", customer)
      render_panel

      expect(page).to have_css(
        %(button[data-prompt="#{website_prompt}"][data-action="click->ai-assistant#usePrompt"]),
        text: I18n.t("ai_assistant.assistant.prompt_labels.create_website")
      )
      expect(page).to have_css(%(button[data-prompt="#{website_prompt}"]), text: website_prompt)
      expect(card_keys).to eq(%w[create_entity create_website new_page enable_module])
    end

    it "follows the flowchart prompt for the platform owner and spans an odd trailing card" do
      owner = find_or_create_platform_owner
      enable_module!("website", customer)

      expect(card_keys(viewer: owner)).to eq(
        %w[create_entity create_flowchart create_website new_page enable_module]
      )
      render_panel(viewer: owner)
      expect(page).to have_css("button[data-prompt]", minimum: 5)
      expect(page).to have_css(%(button.sm\\:odd\\:last\\:col-span-2[data-prompt="#{website_prompt}"]))
    end
  end

  it "renders existing messages and omits the empty state" do
    conversation = create(:ai_assistant_conversation)
    message = create(:ai_assistant_message, conversation: conversation, customer: conversation.customer, body: "Prior turn")
    render_panel(messages: [ message ])
    expect(page).to have_text("Prior turn")
    expect(page).not_to have_css("[data-prompt='Prior turn']")
    expect(page).not_to have_css("button[data-action='click->ai-assistant#copy']")
    expect(page).to have_css("time[datetime]")
    expect(page).to have_css("h2#ai-assistant-title", visible: :all)
    expect(page).not_to have_text(I18n.t("ai_assistant.assistant.what"))
    expect(page).to have_css("##{AiAssistant::Stream::STATUS_ID}[role='status']")
    expect(page).not_to have_text(I18n.t("ai_assistant.assistant.greeting", name: "Ada"))
    expect(page).not_to have_text(I18n.t("ai_assistant.assistant.try"))
    expect(page).not_to have_css("##{AiAssistant::Stream::EMPTY_ID}")
  end

  # Thread traffic is per-conversation so a reply cannot land in a thread the
  # reader has since switched away from; mic transcripts and the chat sidebar
  # ride the user-level stream because they outlive any one thread.
  it "subscribes to both the conversation stream and the user stream" do
    render_panel

    expect(page).to have_css(
      "turbo-cable-stream-source[signed-stream-name]",
      count: 2,
      visible: :all
    )
  end

  # The draft is where the live reply is written before it is persisted; it has
  # to exist on first paint or the first broadcast has nothing to replace.
  it "renders an empty draft slot for the streaming reply" do
    render_panel

    expect(page).to have_css("##{AiAssistant::Stream::DRAFT_ID}", visible: :all)
  end

  it "announces arriving turns without re-reading the starter prompts" do
    render_panel

    expect(page).to have_css(
      "##{AiAssistant::Stream::THREAD_ID}[role='log'][aria-live='polite']",
      visible: :all
    )
    # The scroll container wraps the prompt cards too, so it must not be live.
    expect(page).not_to have_css("[data-ai-assistant-target='thread'][aria-live]", visible: :all)
  end

  describe "regenerate" do
    it "is offered once the thread has a user turn to replay" do
      conversation = create(:ai_assistant_conversation)
      message = create(:ai_assistant_message, conversation: conversation, customer: conversation.customer)

      render_panel(messages: [ message ])

      expect(page).to have_css(
        "button[data-action='click->ai-assistant#regenerate'][data-ai-assistant-target='regenerateButton']"
      )
      expect(page).to have_css(
        "[data-ai-assistant-regenerate-url-value='/#{customer_id}/admin/modules/ai_assistant/messages/regenerate']"
      )
    end

    it "is withheld on an empty thread" do
      render_panel

      expect(page).not_to have_css("button[data-action='click->ai-assistant#regenerate']")
    end

    # Replaying a turn spends a round, so a spent thread must not offer it.
    it "is withheld once the cap is spent" do
      conversation = create(:ai_assistant_conversation)
      spent = Array.new(AiAssistant::Limits::MAX_TURNS) do
        create(:ai_assistant_message, conversation: conversation, customer: conversation.customer)
      end

      render_panel(messages: spent)

      expect(page).not_to have_css("button[data-action='click->ai-assistant#regenerate']")
    end
  end

  describe "conversation limits" do
    def turns(count)
      conversation = create(:ai_assistant_conversation)
      Array.new(count) do
        create(:ai_assistant_message, conversation: conversation, customer: conversation.customer)
      end
    end

    it "exposes the cap values and the conversation the composer posts to" do
      render_panel

      expect(page).to have_css("[data-ai-assistant-conversation-id-value='#{conversation_id}']")
      expect(page).to have_css("[data-ai-assistant-cooldown-ms-value='#{described_class::COOLDOWN_MS}']")
      expect(page).to have_css("[data-ai-assistant-watchdog-ms-value='#{described_class::WATCHDOG_MS}']")
      expect(page).to have_css("[data-ai-assistant-turns-remaining-value='#{AiAssistant::Limits::MAX_TURNS}']")
      expect(page).to have_css("[data-ai-assistant-turns-warning-at-value='#{AiAssistant::Limits::TURNS_WARNING_THRESHOLD}']")
      expect(page).to have_css("[data-ai-assistant-turns-remaining-template-value='#{I18n.t("ai_assistant.assistant.turns_remaining_template")}']")
      expect(page).to have_css("[data-ai-assistant-turns-exhausted-label-value='#{I18n.t("ai_assistant.assistant.turns_exhausted")}']")
      expect(page).to have_css("[data-ai-assistant-connection-lost-label-value='#{I18n.t("ai_assistant.assistant.connection_lost")}']")
      expect(page).to have_css("[data-ai-assistant-stop-failed-label-value='#{I18n.t("ai_assistant.assistant.stop_failed")}']")
      expect(page).to have_css("[data-ai-assistant-regenerate-failed-label-value='#{I18n.t("ai_assistant.assistant.regenerate_failed")}']")
    end

    # Starting a thread is a list operation now, so the composer no longer
    # carries a reset endpoint at all.
    it "no longer advertises a reset endpoint" do
      render_panel

      expect(page).not_to have_css("[data-ai-assistant-reset-url-value]")
      expect(page).not_to have_css("[data-action='click->ai-assistant#reset']")
      expect(rendered_content).not_to include("messages/reset")
    end

    # A counter on a fresh thread is noise, so the slot stays rendered (the
    # controller fills it live) but hidden until the cap is close.
    it "keeps the hint hidden while the cap is far away" do
      render_panel(messages: turns(1))

      expect(page).to have_css("[data-ai-assistant-target='turnsHint'].hidden", visible: :all)
      expect(page).to have_css("[data-ai-assistant-target='turnsHint']", text: "", visible: :all)
    end

    it "counts only the user's own turns against the cap" do
      conversation = create(:ai_assistant_conversation)
      assistant_turns = Array.new(3) do
        create(:ai_assistant_message, :assistant, conversation: conversation, customer: conversation.customer)
      end

      render_panel(messages: assistant_turns)

      expect(page).to have_css("[data-ai-assistant-turns-remaining-value='#{AiAssistant::Limits::MAX_TURNS}']")
    end

    it "warns once the thread nears the cap" do
      spent = AiAssistant::Limits::MAX_TURNS - AiAssistant::Limits::TURNS_WARNING_THRESHOLD
      render_panel(messages: turns(spent))

      expect(page).to have_css(
        "[data-ai-assistant-target='turnsHint']",
        text: I18n.t("ai_assistant.assistant.turns_remaining", count: AiAssistant::Limits::TURNS_WARNING_THRESHOLD)
      )
      expect(page).not_to have_css("[data-ai-assistant-target='turnsHint'].hidden", visible: :all)
    end

    it "tells the user to start a new chat once the cap is spent" do
      render_panel(messages: turns(AiAssistant::Limits::MAX_TURNS))

      expect(page).to have_css(
        "[data-ai-assistant-target='turnsHint']",
        text: I18n.t("ai_assistant.assistant.turns_exhausted")
      )
      expect(page).to have_css("[data-ai-assistant-turns-remaining-value='0']")
    end

    # A box that silently swallows keystrokes reads as broken; the disabled
    # state has to be visible and has to say why.
    it "disables the composer and explains itself once the cap is spent" do
      render_panel(messages: turns(AiAssistant::Limits::MAX_TURNS))

      composer = page.find("textarea#ai_assistant_composer", visible: :all)
      expect(composer[:disabled]).to be_truthy
      expect(composer[:placeholder]).to eq(I18n.t("ai_assistant.assistant.turns_exhausted"))
      expect(composer[:class]).to include("disabled:opacity-60")
      expect(page).to have_css("button[aria-label='#{I18n.t("ai_assistant.assistant.send")}'][disabled]", visible: :all)
    end

    it "leaves the composer usable while the thread has budget" do
      render_panel(messages: turns(1))

      composer = page.find("textarea#ai_assistant_composer")
      expect(composer[:disabled]).to be_falsey
      expect(composer[:placeholder]).to eq(I18n.t("ai_assistant.assistant.placeholder"))
    end
  end

  describe "@ mention menu" do
    it "renders the listbox the composer completes into" do
      render_panel

      expect(page).to have_css(
        "[data-ai-assistant-target='mentionMenu']##{described_class::MENTION_MENU_ID}[role='listbox'].hidden",
        visible: :all
      )
      expect(page).to have_css(
        "[data-ai-assistant-target='mentionMenu'][aria-label='#{I18n.t("ai_assistant.assistant.mention_hint_without_flowchart")}']",
        visible: :all
      )
      expect(page).to have_css("[data-ai-assistant-target='mentionList']", visible: :all)
      # aria-expanded / aria-controls / aria-activedescendant are only valid on
      # the textarea because it declares itself a combobox.
      expect(page).to have_css(
        "textarea#ai_assistant_composer[role='combobox'][aria-autocomplete='list'][aria-haspopup='listbox']"
      )
      expect(page).to have_css(
        "textarea#ai_assistant_composer[aria-controls='#{described_class::MENTION_MENU_ID}'][aria-expanded='false']"
      )
      expect(page).to have_css(
        "textarea#ai_assistant_composer[data-action*='input->ai-assistant#compose']"
      )
      expect(page).to have_css(
        "textarea#ai_assistant_composer[data-action*='compositionend->ai-assistant#compose']"
      )
      expect(page).to have_css(
        "textarea#ai_assistant_composer[data-action*='blur->ai-assistant#closeMentions']"
      )
    end

    it "exposes the endpoint and the translated labels the rows are built from" do
      render_panel

      expect(page).to have_css(
        "[data-ai-assistant-mentions-url-value='/#{customer_id}/admin/modules/ai_assistant/messages/mentions']"
      )
      expect(page).to have_css(
        "[data-ai-assistant-mention-empty-label-value='#{I18n.t("ai_assistant.assistant.mention_empty")}']"
      )
      expect(page).to have_text(I18n.t("ai_assistant.assistant.mention_hint_without_flowchart"))
      expect(page).not_to have_text(I18n.t("ai_assistant.assistant.mention_hint"))

      kinds = JSON.parse(page.find("[data-ai-assistant-mention-kinds-value]", visible: :all)["data-ai-assistant-mention-kinds-value"])
      expect(kinds).to eq(
        "entity" => I18n.t("ai_assistant.assistant.mention_kinds.entity")
      )
    end

    it "exposes flowchart mention kinds to the platform owner" do
      render_panel(viewer: find_or_create_platform_owner)

      expect(page).to have_text(I18n.t("ai_assistant.assistant.mention_hint"))
      kinds = JSON.parse(page.find("[data-ai-assistant-mention-kinds-value]", visible: :all)["data-ai-assistant-mention-kinds-value"])
      expect(kinds).to eq(
        "entity" => I18n.t("ai_assistant.assistant.mention_kinds.entity"),
        "flowchart" => I18n.t("ai_assistant.assistant.mention_kinds.flowchart")
      )
    end
  end

  it "offers a jump control instead of yanking the viewport" do
    render_panel

    expect(page).to have_css(
      "button[data-ai-assistant-target='jumpButton'].hidden",
      text: I18n.t("ai_assistant.assistant.jump_to_latest"),
      visible: :all
    )
    expect(page).to have_css("[data-action*='scroll->ai-assistant#threadScrolled']", visible: :all)
  end

  # The `scroll` event is coalesced to about one a frame, so the gesture itself
  # is what takes the viewport back from the autoscroll mid-stream.
  it "unpins the transcript from the gesture rather than the scroll it causes" do
    render_panel

    action = page.find("[data-ai-assistant-target='thread']", visible: :all)["data-action"]
    expect(action).to include("wheel->ai-assistant#userScrolled")
    expect(action).to include("touchstart->ai-assistant#userScrolled")
    expect(action).to include("touchmove->ai-assistant#userScrolled")
  end

  # The menu's padding and scrollbar are part of it too: letting mousedown
  # through there blurs the composer and closes the menu mid-drag.
  it "suppresses blur across the whole mention menu, not just its rows" do
    render_panel

    expect(page).to have_css(
      "[data-ai-assistant-target='mentionMenu'][data-action='mousedown->ai-assistant#preventBlur pointerdown->ai-assistant#preventBlur']",
      visible: :all
    )
  end

  # Routine attachment validation lands here too, and must not cut across a
  # reply that is still arriving; the controller raises it for a lost
  # connection.
  it "keeps the composer error slot polite" do
    render_panel

    expect(page).to have_css("p##{described_class::ERROR_ID}[role='alert'][aria-live='polite']", visible: :all)
  end

  describe "the escape hatch from a spent thread" do
    def turns(count)
      conversation = create(:ai_assistant_conversation)
      Array.new(count) do
        create(:ai_assistant_message, conversation: conversation, customer: conversation.customer)
      end
    end

    # The chat list owns the write, but below xl it sits behind a disclosure —
    # so the advice in the hint is repeated as a control where it is given.
    it "offers a new chat inline once the cap is spent" do
      render_panel(messages: turns(AiAssistant::Limits::MAX_TURNS))

      button = page.find("[data-ai-assistant-target='newChatButton']")
      expect(button.text.strip).to eq(I18n.t("ai_assistant.assistant.start_new_chat"))
      expect(button["data-action"]).to eq("click->ai-assistant#newChat")
      expect(button[:class]).not_to include("hidden")
    end

    it "keeps it out of the way while the thread still has budget" do
      render_panel(messages: turns(1))

      expect(page).to have_css("[data-ai-assistant-target='newChatButton'].hidden", visible: :all)
    end
  end

  # PendingConfirmation.consume always applies the latest proposal in the
  # thread, so an Apply button on an older panel would promise something the
  # server would not do.
  describe "proposals in the transcript" do
    def proposal(name)
      {
        "kind" => "operation",
        "operation" => "update_entity",
        "invocation_id" => 77,
        "customer_id" => customer_id,
        "plan" => [
          {
            "name" => name, "id" => 12, "breaking" => false,
            "rows" => [ { "kind" => "attribute", "action" => "added", "name" => "Phone", "breaking" => false } ]
          }
        ]
      }
    end

    def thread_with_two_proposals
      conversation = create(:ai_assistant_conversation)
      older = create(
        :ai_assistant_message, :assistant,
        conversation: conversation, customer: conversation.customer,
        metadata: { "pending_confirmation" => proposal("Contact") }
      )
      asked = create(
        :ai_assistant_message,
        conversation: conversation, customer: conversation.customer, body: "Actually, rename it"
      )
      newer = create(
        :ai_assistant_message, :assistant,
        conversation: conversation, customer: conversation.customer,
        metadata: { "pending_confirmation" => proposal("Company") }
      )
      [ older, asked, newer ]
    end

    it "keeps Apply on the newest pending proposal and retires the older one" do
      older, asked, newer = thread_with_two_proposals

      render_panel(messages: [ older, asked, newer ])

      expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(newer)} [data-proposal='pending']")
      expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(older)} [data-proposal='superseded']")
      expect(page).to have_css("button[data-action='click->ai-assistant#applyProposal']", count: 1)
      expect(page).to have_text(I18n.t("ai_assistant.assistant.plan.superseded"))
    end

    it "offers the only pending proposal in the thread" do
      older, = thread_with_two_proposals

      render_panel(messages: [ older ])

      expect(page).to have_css("[data-proposal='pending']")
      expect(page).to have_css("button[data-action='click->ai-assistant#applyProposal']", count: 1)
    end

    # An applied proposal is not a candidate for the active slot, so a thread
    # with nothing pending must not promote one by accident.
    it "leaves an applied proposal stamped and offers nothing" do
      conversation = create(:ai_assistant_conversation)
      applied = create(
        :ai_assistant_message, :assistant,
        conversation: conversation, customer: conversation.customer,
        metadata: { "applied_proposal" => proposal("Contact") }
      )

      render_panel(messages: [ applied ])

      expect(page).to have_css("[data-proposal='applied']")
      expect(page).not_to have_css("button[data-action='click->ai-assistant#applyProposal']")
    end

    # After ReplyWriter retires an older offer, a reload must still show the
    # change list — just not as something the admin can Apply.
    it "keeps a retired proposal visible and does not offer Apply on it" do
      conversation = create(:ai_assistant_conversation)
      retired = create(
        :ai_assistant_message, :assistant,
        conversation: conversation, customer: conversation.customer,
        metadata: { "superseded_proposal" => proposal("Contact") }
      )
      live = create(
        :ai_assistant_message, :assistant,
        conversation: conversation, customer: conversation.customer,
        metadata: { "pending_confirmation" => proposal("Company") }
      )

      render_panel(messages: [ retired, live ])

      expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(retired)} [data-proposal='superseded']")
      expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(live)} [data-proposal='pending']")
      expect(page).to have_css("button[data-action='click->ai-assistant#applyProposal']", count: 1)
    end

    it "exposes the labels the controller writes into a retired panel" do
      render_panel

      expect(page).to have_css("[data-ai-assistant-proposal-apply-label-value='#{I18n.t("ai_assistant.assistant.plan.apply")}']")
      expect(page).to have_css("[data-ai-assistant-proposal-applying-label-value='#{I18n.t("ai_assistant.assistant.plan.applying")}']")
      expect(page).to have_css("[data-ai-assistant-proposal-superseded-label-value='#{I18n.t("ai_assistant.assistant.plan.superseded")}']")
      expect(page).to have_css("[data-ai-assistant-questions-send-label-value='#{I18n.t("ai_assistant.assistant.questions.send")}']")
      expect(page).to have_css("[data-ai-assistant-questions-sending-label-value='#{I18n.t("ai_assistant.assistant.questions.sending")}']")
    end

    it "opens questions only on the newest message" do
      question = {
        "id" => "q1", "prompt" => "Opening hours", "type" => "text",
        "options" => [], "default" => "Mon"
      }
      conversation = create(:ai_assistant_conversation)
      older = create(
        :ai_assistant_message, :assistant,
        conversation: conversation, customer: conversation.customer,
        metadata: { "questions" => [ question ] }
      )
      newer = create(
        :ai_assistant_message, :assistant,
        conversation: conversation, customer: conversation.customer,
        metadata: { "questions" => [ question ] }
      )

      render_panel(messages: [ older, newer ])

      expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(older)} [data-questions='closed']")
      expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(newer)} [data-questions='open']")
    end

    # A second subscription to the same stream identifier makes every appended
    # bubble render twice, so the panel stays the only subscriber.
    it "adds no stream subscription of its own" do
      older, asked, newer = thread_with_two_proposals

      render_panel(messages: [ older, asked, newer ])

      expect(page).to have_css("turbo-cable-stream-source[signed-stream-name]", count: 2, visible: :all)
    end
  end

  it "hides the attach control when the generation vendor does not support images" do
    create(:ai_assistant_provider_settings,
           provider: "deepseek",
           api_key: "sk-deep",
           transcribe_active: false,
           generation_active: true)
    render_panel
    expect(page).not_to have_css("button[aria-label='#{I18n.t("ai_assistant.assistant.attach")}']")
    expect(page).not_to have_css("input[type='file']")
    expect(page).not_to have_text(I18n.t("ai_assistant.assistant.attach"))
    expect(page).to have_css("button[aria-label='#{I18n.t("ai_assistant.assistant.send")}']")
  end
end
