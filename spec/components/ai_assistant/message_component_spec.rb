# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::MessageComponent, type: :component do
  it "renders a user bubble" do
    message = create(:ai_assistant_message, body: "My question")
    render_inline(described_class.new(message: message))
    root = page.find("[data-role='user']")
    expect(root[:class]).to include("group/message")
    expect(root["data-body"]).to eq("My question")
    expect(page).to have_text("My question")
    expect(rendered_content).to include(I18n.t("ai_assistant.assistant.you"))
    expect(page).to have_css("time[datetime='#{message.created_at.iso8601}']")
    expect(page).to have_text(I18n.l(message.created_at, format: :short))
    expect(page).not_to have_css("[data-role='user'] > span[aria-hidden='true']")
    expect(page).not_to have_css("button[data-action='click->ai-assistant#copy']")
    expect(page).not_to have_css("[data-copy-idle]")
    expect(page).not_to have_css("[data-copy-done]")
  end

  it "strips surrounding whitespace from a user body and keeps internal newlines" do
    message = create(:ai_assistant_message, body: "  \nHello\nworld  \n")
    render_inline(described_class.new(message: message))

    expect(page.find("[data-role='user']")["data-body"]).to eq("Hello\nworld")
    expect(rendered_content).to match(/whitespace-pre-line[^>]*>Hello\nworld/)
    expect(rendered_content).not_to match(/whitespace-pre-line[^>]*>\s+Hello/)
    expect(page).to have_text("Hello")
    expect(page).to have_text("world")
  end

  it "renders a per-message copy control on assistant replies only" do
    conversation = create(:ai_assistant_conversation)
    assistant = create(
      :ai_assistant_message,
      :assistant,
      conversation: conversation,
      customer: conversation.customer,
      body: "  Reply  "
    )
    user = create(
      :ai_assistant_message,
      conversation: conversation,
      customer: conversation.customer,
      body: "Ask"
    )

    render_inline(described_class.new(message: assistant))
    assistant_root = page.find("[data-role='assistant']")
    expect(assistant_root[:class]).to include("group/message")
    expect(assistant_root["data-body"]).to eq("Reply")
    expect(page).to have_css("button[data-action='click->ai-assistant#copy']", count: 1)
    copy = page.find("button[data-action='click->ai-assistant#copy']")
    expect(copy[:title]).to eq(I18n.t("ai_assistant.assistant.copy"))
    expect(copy[:"aria-label"]).to eq(I18n.t("ai_assistant.assistant.copy"))
    expect(copy[:class]).to include("pointer-fine:opacity-0")
    expect(copy[:class]).to include("pointer-fine:group-hover/message:opacity-100")
    expect(copy).to have_css("svg[data-copy-idle]")
    expect(copy).to have_css("svg[data-copy-done].hidden")

    render_inline(described_class.new(message: user))
    expect(page).to have_css("[data-role='user'][data-body='Ask']")
    expect(page).not_to have_css("button[data-action='click->ai-assistant#copy']")
    expect(page).not_to have_css("[data-copy-idle]")
    expect(page).not_to have_css("[data-copy-done]")
  end

  it "renders a sparkle avatar on assistant messages only" do
    conversation = create(:ai_assistant_conversation)
    assistant = create(
      :ai_assistant_message,
      :assistant,
      conversation: conversation,
      customer: conversation.customer,
      body: "Done"
    )
    user = create(
      :ai_assistant_message,
      conversation: conversation,
      customer: conversation.customer,
      body: "Ask"
    )

    render_inline(described_class.new(message: assistant))
    expect(page).to have_css("[data-role='assistant'] > span[aria-hidden='true']")

    render_inline(described_class.new(message: user))
    expect(page).to have_css("[data-role='user']")
    expect(page).not_to have_css("[data-role='user'] > span[aria-hidden='true']")
    expect(page).not_to have_css("[data-role='assistant']")
  end

  it "renders a failed assistant bubble" do
    message = create(:ai_assistant_message, :assistant, body: "Nope", status: "failed")
    render_inline(described_class.new(message: message))
    expect(page).to have_text("Nope")
    expect(page).to have_css(".text-danger")
    expect(page).to have_css("[data-role='assistant'] > span[aria-hidden='true']")
    expect(rendered_content).to include("bg-danger-subtle/80")
    expect(rendered_content).to include("ring-danger/10")
    expect(rendered_content).not_to include("bg-danger-subtle px-4")
  end

  it "renders a cancelled assistant bubble" do
    message = create(:ai_assistant_message, :assistant, body: "Stopped.", status: "cancelled")
    render_inline(described_class.new(message: message))
    expect(page).to have_text("Stopped.")
    expect(page).to have_css("[data-role='assistant']")
    expect(page).to have_css(".text-text-muted")
  end

  it "renders markdown and a changes trail" do
    conversation = create(:ai_assistant_conversation)
    message = create(
      :ai_assistant_message,
      :assistant,
      conversation: conversation,
      customer: conversation.customer,
      body: "**Done**",
      metadata: { "changes" => [ { "kind" => "entity", "action" => "created", "name" => "Student" } ] }
    )
    render_inline(described_class.new(message: message))
    expect(page).to have_css("strong", text: "Done")
    expect(page).to have_css("details")
    expect(page).to have_css("summary", text: I18n.t("ai_assistant.assistant.changes.summary"))
    expect(page).to have_css(
      "details li",
      text: I18n.t(
        "ai_assistant.assistant.changes.created",
        kind: I18n.t("ai_assistant.assistant.artifact.kinds.entity"),
        name: "Student"
      ),
      visible: :all
    )
  end

  describe "a proposed update the assistant has not saved" do
    def entity_proposal
      {
        "kind" => "operation",
        "operation" => "update_entity",
        "invocation_id" => 77,
        "customer_id" => 81_721_200,
        "plan" => [
          {
            "name" => "Contact", "id" => 12, "breaking" => false,
            "rows" => [ { "kind" => "attribute", "action" => "added", "name" => "Phone", "breaking" => false } ]
          }
        ]
      }
    end

    def assistant_message(metadata)
      conversation = create(:ai_assistant_conversation)
      create(
        :ai_assistant_message,
        :assistant,
        conversation: conversation,
        customer: conversation.customer,
        body: "Here is what I would change.",
        metadata: metadata
      )
    end

    # Stream.broadcast_message renders this component standalone for a freshly
    # appended reply, which is by definition the newest proposal in the thread.
    it "offers the newest pending proposal by default" do
      render_inline(described_class.new(message: assistant_message("pending_confirmation" => entity_proposal)))

      expect(page).to have_css("[data-proposal='pending']")
      expect(page).to have_css("button[data-action='click->ai-assistant#applyProposal']")
      expect(page).to have_css("button[data-action='click->ai-assistant#refineProposal']")
      expect(page).to have_text(I18n.t("ai_assistant.assistant.plan.subtitle"))
    end

    it "renders an older pending proposal read-only" do
      message = assistant_message("pending_confirmation" => entity_proposal)

      render_inline(described_class.new(message: message, proposal_active: false))

      expect(page).to have_css("[data-proposal='superseded']")
      expect(page).to have_text(I18n.t("ai_assistant.assistant.plan.superseded"))
      expect(page).not_to have_css("button[data-action='click->ai-assistant#applyProposal']")
    end

    # Applied is a fact about the past, so it outranks the actionable states
    # whether or not this turn is still the newest one.
    it "stamps a proposal that has already been applied" do
      message = assistant_message("applied_proposal" => entity_proposal)

      render_inline(described_class.new(message: message, proposal_active: false))

      expect(page).to have_css("[data-proposal='applied']")
      expect(page).to have_text(I18n.t("ai_assistant.assistant.plan.applied"))
      expect(page).not_to have_css("button[data-action='click->ai-assistant#applyProposal']")
    end

    # ReplyWriter moves a declined offer here so a later "yes" cannot apply it.
    # The change list still has to stay in the transcript.
    it "keeps a retired proposal in the transcript, read-only" do
      render_inline(described_class.new(message: assistant_message("superseded_proposal" => entity_proposal)))

      expect(page).to have_css("[data-proposal='superseded']")
      expect(page).to have_text(I18n.t("ai_assistant.assistant.plan.superseded"))
      expect(page).to have_text("Phone")
      expect(page).not_to have_css("button[data-action='click->ai-assistant#applyProposal']")
    end

    it "stamps applied when a message also carries a retired copy of the same offer" do
      render_inline(
        described_class.new(
          message: assistant_message(
            "applied_proposal" => entity_proposal,
            "superseded_proposal" => entity_proposal.merge("plan" => [])
          )
        )
      )

      expect(page).to have_css("[data-proposal='applied']")
      expect(page).not_to have_css("button[data-action='click->ai-assistant#applyProposal']")
    end

    it "stamps a discarded proposal and offers nothing" do
      render_inline(described_class.new(message: assistant_message("declined_proposal" => entity_proposal)))

      expect(page).to have_css("[data-proposal='declined']")
      expect(page).to have_text(I18n.t("ai_assistant.assistant.plan.declined"))
      expect(page).not_to have_css("button[data-action='click->ai-assistant#applyProposal']")
    end

    it "stamps declined ahead of a retired copy on the same message" do
      render_inline(
        described_class.new(
          message: assistant_message(
            "declined_proposal" => entity_proposal,
            "superseded_proposal" => entity_proposal.merge("plan" => [])
          )
        )
      )

      expect(page).to have_css("[data-proposal='declined']")
    end

    it "pins Apply to this message and posts Discard to its discard URL" do
      message = assistant_message("pending_confirmation" => entity_proposal)

      render_inline(described_class.new(message: message))

      apply = page.find("button[data-action='click->ai-assistant#applyProposal']")
      expect(apply["data-ai-assistant-message-id-param"]).to eq(message.id.to_s)
      host = page.find("[data-proposal-discard]")
      expect(host.tag_name).to eq("span")
      form = host.find("form")
      expect(form[:action]).to eq(
        "/#{message.customer_id}/admin/modules/ai_assistant/messages/#{message.id}/discard_proposal"
      )
    end

    it "offers a live pending proposal ahead of a retired one on the same message" do
      render_inline(
        described_class.new(
          message: assistant_message(
            "pending_confirmation" => entity_proposal,
            "superseded_proposal" => entity_proposal.merge("plan" => [])
          )
        )
      )

      expect(page).to have_css("[data-proposal='pending']")
      expect(page).to have_css("button[data-action='click->ai-assistant#applyProposal']")
    end

    it "renders no panel for a turn that proposed nothing" do
      render_inline(described_class.new(message: assistant_message({})))

      expect(page).to have_css("[data-role='assistant']")
      expect(page).not_to have_css("[data-proposal]")
    end

    # A flowchart proposal carries no change plan, and the metadata may be
    # anything at all — neither may break the transcript.
    it "renders no panel for a proposal it cannot lay out" do
      [ entity_proposal.merge("kind" => "flowchart"), "junk", nil ].each do |value|
        render_inline(described_class.new(message: assistant_message("pending_confirmation" => value)))

        expect(page).not_to have_css("[data-proposal]")
      end
    end
  end

  it "renders a reused page as reused rather than created" do
    conversation = create(:ai_assistant_conversation)
    message = create(
      :ai_assistant_message,
      :assistant,
      conversation: conversation,
      customer: conversation.customer,
      body: "Done",
      metadata: {
        "changes" => [
          { "kind" => "page", "action" => "reused", "name" => "Student" }
        ]
      }
    )

    render_inline(described_class.new(message: message))

    expect(page).to have_css("details")
    expect(page).to have_text(
      I18n.t(
        "ai_assistant.assistant.changes.reused",
        kind: I18n.t("ai_assistant.assistant.artifact.kinds.page"),
        name: "Student"
      )
    )
    expect(page).not_to have_text(
      I18n.t(
        "ai_assistant.assistant.changes.created",
        kind: I18n.t("ai_assistant.assistant.artifact.kinds.page"),
        name: "Student"
      )
    )
  end

  it "labels a website page change as a website page" do
    conversation = create(:ai_assistant_conversation)
    message = create(
      :ai_assistant_message,
      :assistant,
      conversation: conversation,
      customer: conversation.customer,
      body: "Done",
      metadata: {
        "changes" => [
          { "kind" => "website_page", "action" => "created", "name" => "Our menu" }
        ]
      }
    )

    render_inline(described_class.new(message: message))

    expect(page).to have_css(
      "details li",
      text: I18n.t(
        "ai_assistant.assistant.changes.created",
        kind: I18n.t("ai_assistant.assistant.artifact.kinds.website_page"),
        name: "Our menu"
      ),
      visible: :all
    )
    expect(page).not_to have_text(
      I18n.t(
        "ai_assistant.assistant.changes.created",
        kind: I18n.t("ai_assistant.assistant.artifact.kinds.entity"),
        name: "Our menu"
      )
    )
  end

  describe "website undo" do
    let(:conversation) { create(:ai_assistant_conversation) }

    before { enable_module!("website", conversation.customer) }

    def website_reply(undo)
      create(:ai_assistant_message, :assistant, conversation: conversation, customer: conversation.customer, body: "Done",
        metadata: { "changes" => [], Websites::Assistant::Undo::KEY => undo })
    end

    def undo_t(key, **options) = I18n.t("ai_assistant.assistant.website.undo.#{key}", **options)

    let(:entries) { { "pages" => [ { "page_id" => 1, "title" => "Menu", "created" => true, "fingerprint" => "x" } ] } }

    it "offers a confirmed Undo form that posts to the reply's undo URL" do
      message = website_reply(entries)

      render_inline(described_class.new(message: message))

      form = page.find("[data-website-undo='available'] form")
      expect(form[:action]).to eq("/#{message.customer_id}/admin/modules/ai_assistant/messages/#{message.id}/undo")
      expect(form["data-turbo-confirm"]).to eq(undo_t("confirm"))
      expect(form).to have_button(undo_t("button"))
      expect(page).not_to have_css("[role='alert']")
    end

    it "shows why an undo was refused next to the button" do
      message = website_reply(entries)

      render_inline(described_class.new(message: message, undo_errors: [ "First.", "Second." ]))

      expect(page).to have_css("[data-website-undo='available'] [role='alert']", text: "First. Second.")
    end

    it "shows an undone reply as undone, with no button" do
      render_inline(described_class.new(message: website_reply(entries.merge("undone_at" => Time.current.iso8601))))

      expect(page).to have_css("[data-website-undo='undone']", text: undo_t("done"))
      expect(page).not_to have_button(undo_t("button"))
    end

    it "offers nothing on a reply that wrote nothing to the website, or on a user message" do
      render_inline(described_class.new(message: website_reply({ "pages" => [] })))
      expect(page).not_to have_css("[data-website-undo]")

      user_message = create(:ai_assistant_message, conversation: conversation, customer: conversation.customer,
        metadata: { Websites::Assistant::Undo::KEY => entries })
      render_inline(described_class.new(message: user_message))
      expect(page).not_to have_css("[data-website-undo]")
    end

    it "places assumptions, the change trail, undo, the plan, and questions in that order" do
      message = create(
        :ai_assistant_message, :assistant,
        conversation: conversation, customer: conversation.customer, body: "Done",
        metadata: {
          "assumptions" => [ "Amount is in your reporting currency." ],
          "changes" => [ { "kind" => "entity", "action" => "created", "name" => "Student" } ],
          Websites::Assistant::Undo::KEY => entries,
          "pending_confirmation" => {
            "kind" => "operation",
            "plan" => [
              {
                "name" => "Contact", "id" => 12, "breaking" => false,
                "rows" => [ { "kind" => "attribute", "action" => "added", "name" => "Phone", "breaking" => false } ]
              }
            ]
          },
          "questions" => [
            {
              "id" => "q1", "prompt" => "Opening hours", "type" => "text",
              "options" => [], "default" => "Mon"
            }
          ]
        }
      )

      render_inline(described_class.new(message: message))

      html = rendered_content
      expect(html.index("data-assumptions")).to be < html.index("What I changed")
      expect(html.index("What I changed")).to be < html.index("data-website-undo")
      expect(html.index("data-website-undo")).to be < html.index("data-proposal=")
      expect(html.index("data-proposal=")).to be < html.index("data-questions=")
    end

    it "offers no Undo while the Website module is off, but still shows an undone reply" do
      enable_module!("website", conversation.customer, status: :suspended)

      render_inline(described_class.new(message: website_reply(entries)))
      expect(page).not_to have_css("[data-website-undo]")

      render_inline(described_class.new(message: website_reply(entries.merge("undone_at" => Time.current.iso8601))))
      expect(page).to have_css("[data-website-undo='undone']")
    end
  end

  describe "assumptions and questions" do
    def clarifying_question
      {
        "id" => "q1",
        "prompt" => "Opening hours",
        "type" => "text",
        "options" => [],
        "default" => "Mon–Sat"
      }
    end

    def assistant_with(metadata)
      conversation = create(:ai_assistant_conversation)
      create(
        :ai_assistant_message, :assistant,
        conversation: conversation, customer: conversation.customer,
        body: "Two lists are specific to your team.",
        metadata: metadata
      )
    end

    it "lists assumptions under the bubble and ignores blanks, non-strings, and extras past five" do
      message = assistant_with(
        "assumptions" => [ "  Keep currency.  ", "", nil, 7, "Second.", "Third.", "Fourth.", "Fifth.", "Sixth." ]
      )

      render_inline(described_class.new(message: message))

      items = page.all("[data-assumptions] li").map(&:text)
      expect(page).to have_text(I18n.t("ai_assistant.assistant.assumptions.title"))
      expect(page).to have_text(I18n.t("ai_assistant.assistant.assumptions.hint"))
      expect(items).to eq([ "  Keep currency.  ", "Second.", "Third.", "Fourth.", "Fifth." ])
    end

    it "renders no assumptions or questions on a user message" do
      conversation = create(:ai_assistant_conversation)
      message = create(
        :ai_assistant_message,
        conversation: conversation, customer: conversation.customer,
        metadata: { "assumptions" => [ "Nope" ], "questions" => [ clarifying_question ] }
      )

      render_inline(described_class.new(message: message))

      expect(page).not_to have_css("[data-assumptions]")
      expect(page).not_to have_css("[data-questions]")
    end

    it "renders no assumptions list when the payload is empty or the wrong shape" do
      [ nil, "nope", [], [ "", nil ] ].each do |value|
        render_inline(described_class.new(message: assistant_with("assumptions" => value)))

        expect(page).not_to have_css("[data-assumptions]")
      end
    end

    it "honours an explicit questions_active flag without querying later messages" do
      message = assistant_with("questions" => [ clarifying_question ])
      later = create(
        :ai_assistant_message,
        conversation: message.conversation, customer: message.customer, body: "Later"
      )
      expect(later.id).to be > message.id
      allow(message.conversation).to receive(:messages).and_call_original
      expect(message.conversation).not_to receive(:messages)

      render_inline(described_class.new(message: message, questions_active: true))
      expect(page).to have_css("[data-questions='open']")

      render_inline(described_class.new(message: message, questions_active: false))
      expect(page).to have_css("[data-questions='closed']")
    end

    it "opens the card when no later message exists" do
      message = assistant_with("questions" => [ clarifying_question ])

      render_inline(described_class.new(message: message))

      expect(page).to have_css("[data-questions='open']")
    end

    it "closes the card when a later message exists" do
      message = assistant_with("questions" => [ clarifying_question ])
      create(:ai_assistant_message, conversation: message.conversation, customer: message.customer, body: "Later")

      render_inline(described_class.new(message: message))

      expect(page).to have_css("[data-questions='closed']")
    end

    it "does not query later messages when there are no questions" do
      message = assistant_with({})
      allow(message.conversation).to receive(:messages).and_call_original
      expect(message.conversation).not_to receive(:messages)

      render_inline(described_class.new(message: message))

      expect(page).not_to have_css("[data-questions]")
    end

    it "renders the answered note in zh-CN on a closed card" do
      message = assistant_with("questions" => [ clarifying_question ])

      I18n.with_locale(:"zh-CN") do
        render_inline(described_class.new(message: message, questions_active: false))

        expect(page).to have_text(I18n.t("ai_assistant.assistant.questions.answered", locale: :"zh-CN"))
      end
    end
  end

  describe "generated form links" do
    let(:customer) { create(:customer) }
    let(:conversation) { create(:ai_assistant_conversation, customer: customer) }

    def form(**attributes)
      create(:page, customer: customer, launched: true, **attributes)
    end

    def reply_linking(*forms, role: "assistant")
      create(
        :ai_assistant_message,
        role: role, conversation: conversation, customer: customer, body: "Built your forms.",
        metadata: { "page_links" => forms.map { |record| { "id" => record.id, "name" => record.name } } }
      )
    end

    it "links each form to its maintenance preview in a new tab" do
      course = form(name: "Course")
      render_inline(described_class.new(message: reply_linking(course)))

      link = page.find("[data-page-links] a[data-page-link='#{course.id}']")
      expect(link[:href]).to eq("/#{customer.id}/admin/maintenance/pages/#{course.id}/preview")
      expect(link[:target]).to eq("_blank")
      expect(link[:rel]).to eq("noopener noreferrer")
      expect(link).to have_text("Course")
      expect(link).to have_text(I18n.t("ai_assistant.assistant.page_links.subtitle"))
      expect(link).to have_text(I18n.t("ai_assistant.assistant.page_links.open"))
      expect(link).to have_css(".sr-only", text: I18n.t("ai_assistant.assistant.page_links.new_tab"))
      expect(page).to have_css("ul[aria-label='#{I18n.t("ai_assistant.assistant.page_links.title")}']")
    end

    it "shows the form's current name rather than the name stored with the reply" do
      course = form(name: "Course")
      message = reply_linking(course)
      course.update!(name: "Course catalogue")

      render_inline(described_class.new(message: message))

      expect(page).to have_css("a[data-page-link='#{course.id}']", text: "Course catalogue")
    end

    it "drops forms that were deleted, taken offline, or belong to another tenant" do
      kept = form(name: "Kept")
      offline = form(name: "Offline")
      deleted = form(name: "Deleted")
      foreign = create(:page, customer: create(:customer), launched: true, name: "Foreign")
      message = reply_linking(kept, offline, deleted, foreign)
      offline.update!(launched: false)
      deleted.soft_delete

      render_inline(described_class.new(message: message))

      expect(page).to have_css("a[data-page-link]", count: 1)
      expect(page).to have_css("a[data-page-link='#{kept.id}']")
    end

    it "renders no link list without linkable forms or on a user bubble" do
      course = form
      render_inline(described_class.new(message: reply_linking(course, role: "user")))
      expect(page).not_to have_css("[data-page-links]")

      malformed = create(
        :ai_assistant_message, :assistant, conversation: conversation, customer: customer, body: "Done.",
        metadata: { "page_links" => ["oops", { "id" => "x" }, { "name" => "No id" }] }
      )
      render_inline(described_class.new(message: malformed))
      expect(page).not_to have_css("[data-page-links]")
    end

    it "labels the link in zh-CN" do
      course = form(name: "课程")
      I18n.with_locale(:"zh-CN") do
        render_inline(described_class.new(message: reply_linking(course)))

        expect(page).to have_text(I18n.t("ai_assistant.assistant.page_links.open", locale: :"zh-CN"))
        expect(page).to have_text(I18n.t("ai_assistant.assistant.page_links.subtitle", locale: :"zh-CN"))
      end
    end
  end

  describe "a sub-system build" do
    let(:conversation) { create(:ai_assistant_conversation) }

    def build_reply(status:, conversation: self.conversation)
      build = AiAssistant::SubsystemBuild.create!(customer_id: conversation.customer_id, conversation: conversation,
                                                  user: conversation.user, status: status, blueprint: { "domain" => "School" })
      message = create(:ai_assistant_message, :assistant, conversation: conversation, customer: conversation.customer,
                                                          metadata: { "subsystem_build" => { "id" => build.id } })
      [message, build]
    end

    it "shows a running build with a confirmed Cancel button" do
      message, = build_reply(status: "running")

      render_inline(described_class.new(message: message))

      expect(page).to have_css("[data-subsystem-build='running']", text: I18n.t("ai_assistant.subsystems.status.running"))
      form = page.find("form[action$='/messages/#{message.id}/cancel_build']")
      expect(form["data-turbo-confirm"]).to eq(I18n.t("ai_assistant.subsystems.cancel.confirm"))
      expect(form).to have_button(I18n.t("ai_assistant.subsystems.cancel.button"))
    end

    it "keeps Cancel while the build waits for answers" do
      message, = build_reply(status: "waiting_for_answers")

      render_inline(described_class.new(message: message))

      expect(page).to have_css("[data-subsystem-build='waiting_for_answers']", text: I18n.t("ai_assistant.subsystems.status.waiting_for_answers"))
      expect(page).to have_button(I18n.t("ai_assistant.subsystems.cancel.button"))
    end

    it "shows an ended build's status without Cancel" do
      %w[finished failed cancelled].each do |status|
        message, = build_reply(status: status)

        render_inline(described_class.new(message: message))

        expect(page).to have_css("[data-subsystem-build='#{status}']", text: I18n.t("ai_assistant.subsystems.status.#{status}"))
        expect(page).not_to have_button(I18n.t("ai_assistant.subsystems.cancel.button"))
      end
    end

    it "ignores a build from another conversation or tenant" do
      message, = build_reply(status: "running")
      other, = build_reply(status: "running", conversation: create(:ai_assistant_conversation))
      message.update!(metadata: { "subsystem_build" => { "id" => other.metadata_json.dig("subsystem_build", "id") } })

      render_inline(described_class.new(message: message))

      expect(page).not_to have_css("[data-subsystem-build]")
    end

    it "renders the status in Chinese" do
      message, = build_reply(status: "running")

      I18n.with_locale(:"zh-CN") { render_inline(described_class.new(message: message)) }

      expect(page).to have_text(I18n.t("ai_assistant.subsystems.status.running", locale: :"zh-CN"))
      expect(page).to have_button(I18n.t("ai_assistant.subsystems.cancel.button", locale: :"zh-CN"))
    end
  end
end
