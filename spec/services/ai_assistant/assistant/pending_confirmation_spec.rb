# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::PendingConfirmation do
  ConfirmationResult = Struct.new(:confirmation_applied)

  let(:customer) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }
  let(:entity) { create(:entity, customer: customer, name: "Student") }

  def park_invocation!(overrides = {})
    create(
      :operation_invocation,
      :awaiting_confirmation,
      customer: customer,
      user: conversation.user,
      operation: "update_entity",
      conversation_id: conversation.id,
      **overrides
    )
  end

  def proposal(invocation = park_invocation!, plan_rows: plan)
    {
      "kind" => "operation",
      "operation" => "update_entity",
      "invocation_id" => invocation.id,
      "customer_id" => customer.id,
      "plan" => plan_rows
    }
  end

  def plan
    [{
      "name" => "Student",
      "id" => entity.id,
      "breaking" => false,
      "rows" => [{ "kind" => "attribute", "action" => "added", "name" => "Notes", "html_type" => "textarea", "breaking" => false }]
    }]
  end

  def flowchart_document
    {
      "intent" => "apply_flowchart",
      "reply" => "Updating flow.",
      "flowchart" => { "name" => "Create Student" },
      "updates_confirmed" => false
    }
  end

  def park!(pending, extra = {})
    create(
      :ai_assistant_message,
      :assistant,
      conversation: conversation,
      customer: customer,
      metadata: { "pending_confirmation" => pending }.merge(extra)
    )
  end

  def consume_confirmation(body: "Yes", applied: false, metadata: {})
    user_message = create(
      :ai_assistant_message,
      conversation: conversation,
      customer: customer,
      body: body,
      metadata: metadata
    )
    generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: user_message
    )
    AiAssistant::Assistant::GenerationLifecycle.claim!(generation)
    result = described_class.consume(
      conversation: conversation,
      user_message: user_message,
      generation: generation
    ) do |stored|
      block_given? ? yield(stored) : ConfirmationResult.new(applied)
    end
    [result, generation]
  end

  it "resolves the latest same-tenant proposal for an explicit confirmation" do
    parked = proposal
    park!(parked)

    result, = consume_confirmation { |stored| stored }

    expect(result).to eq(parked)
  end

  it "accepts ordinary sentence-ending punctuation on an explicit confirmation" do
    parked = proposal
    park!(parked)

    result, = consume_confirmation(body: "Yes.") { |stored| stored }

    expect(result).to eq(parked)
  end

  [
    "Yes",
    "yes!",
    "Yes, please",
    "Ok, go ahead!",
    "sure, do it",
    "Confirmed.",
    "Yes, thank you",
    "yes thank you please",
    "确认",
    "请确认",
    "好的。",
    "是的"
  ].each do |body|
    it "treats #{body.inspect} as a bare confirmation" do
      parked = proposal
      park!(parked)

      result, = consume_confirmation(body: body) { |stored| stored }

      expect(result).to eq(parked)
    end
  end

  [
    "Yes, and add Phone",
    "go ahead and add phone too",
    "maybe",
    "not yet",
    "确认一下这个字段要不要加",
    "You sure?",
    "you sure",
    "you ok",
    "sure?",
    "ok?",
    "确认？"
  ].each do |body|
    it "does not treat #{body.inspect} as confirmation" do
      park!(proposal)

      result, = consume_confirmation(body: body) { raise "must not yield" }

      expect(result).to be_nil
    end
  end

  it "does not resolve a proposal from another conversation in the same tenant" do
    other_conversation = create(:ai_assistant_conversation, customer: customer)
    invocation = create(
      :operation_invocation,
      :awaiting_confirmation,
      customer: customer,
      operation: "update_entity",
      conversation_id: other_conversation.id
    )
    create(
      :ai_assistant_message,
      :assistant,
      conversation: other_conversation,
      customer: customer,
      metadata: { "pending_confirmation" => proposal(invocation) }
    )

    result, = consume_confirmation { raise "must not yield" }

    expect(result).to be_nil
  end

  it "rejects proposal metadata pinned to another tenant" do
    other_customer = create(:customer)
    invocation = create(
      :operation_invocation,
      :awaiting_confirmation,
      customer: other_customer,
      operation: "update_entity",
      conversation_id: conversation.id
    )
    park!(proposal(invocation).merge("customer_id" => other_customer.id))

    result, = consume_confirmation { raise "must not yield" }

    expect(result).to be_nil
  end

  it "rejects an operation proposal whose invocation is not awaiting confirmation" do
    invocation = park_invocation!(status: "succeeded")
    park!(proposal(invocation))

    result, = consume_confirmation { raise "must not yield" }

    expect(result).to be_nil
  end

  it "rejects an operation proposal whose invocation belongs to another conversation" do
    other = create(:ai_assistant_conversation, customer: customer)
    invocation = park_invocation!(conversation_id: other.id)
    park!(proposal(invocation))

    result, = consume_confirmation { raise "must not yield" }

    expect(result).to be_nil
  end

  it "rejects malformed proposal metadata without a supported kind" do
    park!(proposal.merge("kind" => "page"))

    result, = consume_confirmation { raise "must not yield" }

    expect(result).to be_nil
  end

  it "rejects a retired entity proposal kind" do
    park!(
      "kind" => "entity",
      "customer_id" => customer.id,
      "document" => { "entities" => [{ "name" => "Student" }] },
      "targets" => [{ "id" => entity.id, "name" => "Student", "version_id" => 1 }]
    )

    result, = consume_confirmation { raise "must not yield" }

    expect(result).to be_nil
  end

  it "removes a successfully consumed proposal so it cannot be replayed" do
    parked = proposal
    proposal_message = park!(parked)

    result, generation = consume_confirmation(applied: true)

    expect(result.confirmation_applied).to eq(true)
    metadata = proposal_message.reload.metadata_json
    expect(metadata).not_to have_key("pending_confirmation")
    expect(metadata.fetch("confirmation_consumed_by_generation_id")).to eq(generation.id)

    replay, = consume_confirmation { raise "must not replay" }

    expect(replay).to have_attributes(
      body: I18n.t("ai_assistant.assistant.proposal_not_pending"),
      status: "complete",
      effects: []
    )
    expect(proposal_message.reload.metadata_json.fetch("applied_proposal")).to eq(parked)
  end

  it "keeps the consumed proposal in the transcript as the applied one" do
    parked = proposal
    proposal_message = park!(parked)

    consume_confirmation(applied: true)

    metadata = proposal_message.reload.metadata_json
    expect(metadata).not_to have_key("pending_confirmation")
    expect(metadata.fetch("applied_proposal")).to eq(parked)
    expect(metadata.fetch("applied_proposal").fetch("plan")).to eq(plan)
  end

  it "does not record an applied proposal when nothing was applied" do
    proposal_message = park!(proposal)

    consume_confirmation(applied: false)

    expect(proposal_message.reload.metadata_json).not_to have_key("applied_proposal")
  end

  describe ".build" do
    let(:flowchart) { create(:flowchart, :simple, customer: customer, name: "Create Student") }

    it "carries the plan the admin reviews when one is given" do
      built = described_class.build(
        kind: "flowchart",
        document: flowchart_document,
        customer: customer,
        record: flowchart,
        plan: plan
      )
      expect(built.fetch("plan")).to eq(plan)
    end

    it "omits the plan key entirely when there is nothing to review" do
      built = described_class.build(
        kind: "flowchart",
        document: flowchart_document,
        customer: customer,
        record: flowchart
      )
      expect(built).not_to have_key("plan")
    end

    it "pins every target it is given with its current version" do
      built = described_class.build(
        kind: "flowchart",
        document: flowchart_document,
        customer: customer,
        record: flowchart
      )

      expect(built.fetch("targets").map { |target| target["name"] }).to eq(["Create Student"])
      expect(built.fetch("targets").first.fetch("version_id")).to eq(flowchart.current_line_head_version_id)
    end
  end

  describe "the plan is display only" do
    it "accepts a proposal whose plan has been rewritten" do
      parked = proposal.merge(
        "plan" => [{ "name" => "Student", "rows" => [{ "kind" => "identity", "action" => "modified", "field" => "name_slug" }] }]
      )
      park!(parked)

      result, = consume_confirmation { |stored| stored }

      expect(result).to eq(parked)
    end

    it "does not let a plan naming another tenant's entity widen the proposal" do
      park!(proposal.merge("customer_id" => create(:customer).id))

      result, = consume_confirmation { raise "must not yield" }

      expect(result).to be_nil
    end
  end

  it "retains a proposal when confirmed persistence is not applied" do
    parked = proposal
    proposal_message = park!(parked)

    result, = consume_confirmation(applied: false)

    expect(result.confirmation_applied).to eq(false)
    expect(proposal_message.reload.metadata_json.fetch("pending_confirmation")).to eq(parked)
    expect(proposal_message.metadata_json).not_to have_key(
      "confirmation_consumed_by_generation_id"
    )
  end

  describe "which proposal a decision targets" do
    def reply!(body)
      create(
        :ai_assistant_message,
        :assistant,
        conversation: conversation,
        customer: customer,
        body: body
      )
    end

    it "applies a typed yes only when the latest complete assistant message is the pending one" do
      parked = proposal
      proposal_message = park!(parked)

      yielded = nil
      consume_confirmation do |stored|
        yielded = stored
        ConfirmationResult.new(true)
      end

      expect(yielded).to eq(parked)
      expect(proposal_message.reload.metadata_json).not_to have_key("pending_confirmation")
    end

    it "applies a pinned yes to the named proposal even after a later assistant reply" do
      parked = proposal
      proposal_message = park!(parked)
      reply!("Do you also want a Phone field?")

      yielded = nil
      consume_confirmation(metadata: { "confirms_message_id" => proposal_message.id }) do |stored|
        yielded = stored
        ConfirmationResult.new(true)
      end

      expect(yielded).to eq(parked)
      expect(proposal_message.reload.metadata_json.fetch("applied_proposal")).to eq(parked)
    end

    it "returns a notice and does not yield when the pinned target is no longer pending" do
      parked = proposal
      proposal_message = park!(parked)
      metadata = proposal_message.metadata_json.deep_dup
      applied = metadata.delete("pending_confirmation")
      metadata["applied_proposal"] = applied
      proposal_message.update!(metadata: metadata)

      result, = consume_confirmation(
        metadata: { "confirms_message_id" => proposal_message.id }
      ) { raise "must not yield" }

      expect(result).to have_attributes(
        body: I18n.t("ai_assistant.assistant.proposal_not_pending"),
        status: "complete",
        effects: []
      )
      expect(proposal_message.reload.metadata_json).not_to have_key("pending_confirmation")
      expect(proposal_message.metadata_json.fetch("applied_proposal")).to eq(parked)
    end

    it "returns a notice when the pinned target cannot be found" do
      park!(proposal)

      result, = consume_confirmation(metadata: { "confirms_message_id" => 0 }) { raise "must not yield" }

      expect(result).to have_attributes(
        body: I18n.t("ai_assistant.assistant.proposal_not_pending"),
        status: "complete",
        effects: []
      )
    end

    # Regression F1: a bare "yes" answering a later question must not apply
    # a proposal offered several turns ago.
    it "does not apply a typed yes after a later complete assistant reply" do
      parked = proposal
      proposal_message = park!(parked)
      reply!("Do you also want a Phone field?")

      result, = consume_confirmation { raise "must not yield" }

      expect(result).to be_nil
      expect(proposal_message.reload.metadata_json.fetch("pending_confirmation")).to eq(parked)
    end

    it "still applies a typed yes to the newest proposal when it is the latest complete assistant message" do
      park!(proposal)
      reply!("An answer to a question about the first one.")
      newer = proposal.merge("plan" => plan + [{ "name" => "Second" }])
      newest_message = park!(newer)

      yielded = nil
      consume_confirmation do |stored|
        yielded = stored
        ConfirmationResult.new(true)
      end

      expect(yielded).to eq(newer)
      expect(newest_message.reload.metadata_json).not_to have_key("pending_confirmation")
    end

    it "finds nothing when the only assistant messages carry no proposal" do
      reply!("Nothing is pending.")

      result, = consume_confirmation { raise "must not yield" }

      expect(result).to be_nil
    end
  end

  describe "re-rendering the panel that was applied" do
    it "replaces the proposal's message after a consume that applied" do
      parked = proposal
      proposal_message = park!(parked)

      expect(AiAssistant::Stream).to receive(:broadcast_message_replace) do |message|
        expect(message.id).to eq(proposal_message.id)
        expect(message.metadata_json).not_to have_key("pending_confirmation")
        expect(message.metadata_json.fetch("applied_proposal")).to eq(parked)
      end

      consume_confirmation(applied: true)
    end

    it "does not replace anything when the consume did not apply" do
      park!(proposal)

      expect(AiAssistant::Stream).not_to receive(:broadcast_message_replace)

      consume_confirmation(applied: false)
    end

    it "does not replace anything when there was no proposal to consume" do
      expect(AiAssistant::Stream).not_to receive(:broadcast_message_replace)

      consume_confirmation(applied: true)
    end

    it "does not replace anything when the message was not an explicit confirmation" do
      park!(proposal)

      expect(AiAssistant::Stream).not_to receive(:broadcast_message_replace)

      consume_confirmation(body: "What would that change?", applied: true)
    end

    it "broadcasts once the lock the write took has been released" do
      park!(proposal)
      baseline = ActiveRecord::Base.connection.open_transactions
      depth_at_broadcast = nil
      depth_inside_lock = nil
      allow(AiAssistant::Stream).to receive(:broadcast_message_replace) do
        depth_at_broadcast = ActiveRecord::Base.connection.open_transactions
      end

      consume_confirmation do
        depth_inside_lock = ActiveRecord::Base.connection.open_transactions
        ConfirmationResult.new(true)
      end

      expect(depth_inside_lock).to be > baseline
      expect(depth_at_broadcast).to eq(baseline)
    end
  end

  describe "at most one live proposal in a thread" do
    it "moves an older pending offer to superseded_proposal and supersedes the invocation" do
      invocation = park_invocation!
      parked = proposal(invocation)
      first = park!(parked)

      described_class.retire_open!(conversation)

      metadata = first.reload.metadata_json
      expect(metadata).not_to have_key("pending_confirmation")
      expect(metadata.fetch("superseded_proposal")).to eq(parked)
      expect(invocation.reload.status).to eq("superseded")
    end

    it "does not apply a declined proposal after a later one has been applied" do
      park!(proposal)
      described_class.retire_open!(conversation)
      second = proposal.merge("plan" => plan + [{ "name" => "Second" }])
      park!(second)

      yielded = []
      consume_confirmation do |stored|
        yielded << stored
        ConfirmationResult.new(true)
      end
      expect(yielded).to eq([second])

      later = :not_yielded
      consume_confirmation do |stored|
        later = stored
        ConfirmationResult.new(true)
      end
      expect(later).to eq(:not_yielded)
    end

    it "does not treat a consumed proposal whose document mentions the key as still live" do
      parked = proposal
      decoy = park!(parked.merge("plan" => [{ "name" => "pending_confirmation" }]))
      metadata = decoy.metadata_json.deep_dup
      applied = metadata.delete("pending_confirmation")
      metadata["applied_proposal"] = applied
      decoy.update!(metadata: metadata)
      live = park!(proposal)

      expect(conversation.messages.with_pending_proposal).to contain_exactly(live)
    end

    it "treats a missing key and an empty metadata object as not pending" do
      missing = create(
        :ai_assistant_message, :assistant,
        conversation: conversation, customer: customer, metadata: {}
      )
      empty_object = create(
        :ai_assistant_message, :assistant,
        conversation: conversation, customer: customer,
        metadata: { "changes" => [] }
      )

      expect(conversation.messages.with_pending_proposal).not_to include(missing, empty_object)
    end
  end

  describe "typed decline" do
    def expect_declined(proposal_message, parked, invocation, generation)
      metadata = proposal_message.reload.metadata_json
      expect(metadata).not_to have_key("pending_confirmation")
      expect(metadata.fetch("declined_proposal")).to eq(parked)
      expect(invocation.reload).to be_declined
      expect(invocation.confirmed_by).to eq(conversation.user)
      expect(invocation.confirmed_at).to be_present
      expect(generation.reload.status).to eq("running")
    end

    [
      "no",
      "No, thanks",
      "No thank you",
      "cancel it",
      "不用了，谢谢",
      "算了",
      "取消"
    ].each do |body|
      it "treats #{body.inspect} as a bare rejection" do
        invocation = park_invocation!
        parked = proposal(invocation)
        proposal_message = park!(parked)

        result, generation = consume_confirmation(body: body) { raise "must not yield" }

        expect(result).to have_attributes(
          body: I18n.t("ai_assistant.assistant.plan.declined"),
          status: "complete",
          effects: []
        )
        expect_declined(proposal_message, parked, invocation, generation)
      end
    end

    [
      "no?",
      "no, add a phone field instead"
    ].each do |body|
      it "does not treat #{body.inspect} as a rejection" do
        parked = proposal
        proposal_message = park!(parked)

        result, = consume_confirmation(body: body) { raise "must not yield" }

        expect(result).to be_nil
        expect(proposal_message.reload.metadata_json.fetch("pending_confirmation")).to eq(parked)
      end
    end

    it "replaces the proposal's message after a typed decline" do
      parked = proposal
      proposal_message = park!(parked)

      expect(AiAssistant::Stream).to receive(:broadcast_message_replace) do |message|
        expect(message.id).to eq(proposal_message.id)
        expect(message.metadata_json).not_to have_key("pending_confirmation")
        expect(message.metadata_json.fetch("declined_proposal")).to eq(parked)
      end

      consume_confirmation(body: "no") { raise "must not yield" }
    end

    it "broadcasts once the lock the write took has been released" do
      park!(proposal)
      baseline = ActiveRecord::Base.connection.open_transactions
      depth_at_broadcast = nil
      allow(AiAssistant::Stream).to receive(:broadcast_message_replace) do
        depth_at_broadcast = ActiveRecord::Base.connection.open_transactions
      end

      consume_confirmation(body: "no") { raise "must not yield" }

      expect(depth_at_broadcast).to eq(baseline)
    end

    it "ignores a pin on a decline and declines the latest typed target instead" do
      older = park!(proposal)
      invocation = park_invocation!
      parked = proposal(invocation)
      latest = park!(parked)

      consume_confirmation(
        body: "no",
        metadata: { "confirms_message_id" => older.id }
      ) { raise "must not yield" }

      expect(older.reload.metadata_json).to have_key("pending_confirmation")
      expect(latest.reload.metadata_json).to have_key("declined_proposal")
      expect(invocation.reload).to be_declined
    end
  end

  describe "a proposal that also carries questions" do
    let(:questions) { [{ "id" => "q1", "prompt" => "Do you also want a Phone field?" }] }

    it "does not treat a typed yes or no as a decision" do
      parked = proposal
      proposal_message = park!(parked, "questions" => questions)

      %w[Yes no].each do |body|
        result, = consume_confirmation(body: body) { raise "must not yield" }
        expect(result).to be_nil
      end
      expect(proposal_message.reload.metadata_json.fetch("pending_confirmation")).to eq(parked)
    end

    it "still applies a pinned approve" do
      parked = proposal
      proposal_message = park!(parked, "questions" => questions)

      yielded = nil
      consume_confirmation(metadata: { "confirms_message_id" => proposal_message.id }) do |stored|
        yielded = stored
        ConfirmationResult.new(true)
      end

      expect(yielded).to eq(parked)
      expect(proposal_message.reload.metadata_json.fetch("applied_proposal")).to eq(parked)
    end
  end

  describe "a settled proposal on the latest message" do
    it "returns a notice for a typed yes after the proposal was declined" do
      parked = proposal
      proposal_message = park!(parked)
      consume_confirmation(body: "no") { raise "must not yield" }

      result, = consume_confirmation { raise "must not yield" }

      expect(result).to have_attributes(
        body: I18n.t("ai_assistant.assistant.proposal_not_pending"),
        status: "complete",
        effects: []
      )
      expect(proposal_message.reload.metadata_json.fetch("declined_proposal")).to eq(parked)
    end
  end

  describe "flowchart proposal decline" do
    it "only moves the pending metadata" do
      parked = {
        "kind" => "flowchart",
        "customer_id" => customer.id,
        "document" => flowchart_document,
        "targets" => [{ "id" => 1, "name" => "Create Student", "version_id" => 1 }]
      }
      stray = park_invocation!
      proposal_message = park!(parked)

      result, = consume_confirmation(body: "no") { raise "must not yield" }

      expect(result).to have_attributes(
        body: I18n.t("ai_assistant.assistant.plan.declined"),
        status: "complete"
      )
      expect(proposal_message.reload.metadata_json.fetch("declined_proposal")).to eq(parked)
      expect(stray.reload).to be_awaiting_confirmation
    end
  end

  describe "invocation scoping on decline" do
    it "does not decline an invocation from another conversation" do
      other = create(:ai_assistant_conversation, customer: customer)
      invocation = park_invocation!(conversation_id: other.id)
      parked = proposal(invocation)
      proposal_message = park!(parked)

      consume_confirmation(body: "no") { raise "must not yield" }

      expect(proposal_message.reload.metadata_json).to have_key("declined_proposal")
      expect(invocation.reload).to be_awaiting_confirmation
    end

    it "does not decline an invocation from another tenant" do
      other_customer = create(:customer)
      invocation = create(
        :operation_invocation,
        :awaiting_confirmation,
        customer: other_customer,
        operation: "update_entity"
      )
      parked = proposal(invocation).merge("customer_id" => other_customer.id)
      proposal_message = park!(parked)

      consume_confirmation(body: "no") { raise "must not yield" }

      expect(proposal_message.reload.metadata_json).to have_key("declined_proposal")
      expect(invocation.reload).to be_awaiting_confirmation
    end
  end

  describe "a generation that is no longer current" do
    it "returns nil and writes nothing on a typed yes" do
      parked = proposal
      proposal_message = park!(parked)
      user_message = create(
        :ai_assistant_message,
        conversation: conversation,
        customer: customer,
        body: "Yes"
      )
      generation = AiAssistant::Assistant::GenerationLifecycle.start!(
        conversation: conversation,
        user_message: user_message
      )
      AiAssistant::Assistant::GenerationLifecycle.claim!(generation)
      newer = create(
        :ai_assistant_message,
        conversation: conversation,
        customer: customer,
        body: "Newer"
      )
      AiAssistant::Assistant::GenerationLifecycle.start!(
        conversation: conversation,
        user_message: newer
      )

      result = described_class.consume(
        conversation: conversation,
        user_message: user_message,
        generation: generation
      ) { raise "must not yield" }

      expect(result).to be_nil
      expect(proposal_message.reload.metadata_json.fetch("pending_confirmation")).to eq(parked)
    end
  end

  describe ".decline!" do
    it "returns false when the message is not an assistant proposal" do
      message = create(:ai_assistant_message, conversation: conversation, customer: customer)

      declined = conversation.with_lock do
        described_class.decline!(message, actor: conversation.user)
      end

      expect(declined).to eq(false)
    end

    it "returns false when nothing is pending" do
      message = create(
        :ai_assistant_message, :assistant,
        conversation: conversation, customer: customer, metadata: {}
      )

      declined = conversation.with_lock do
        described_class.decline!(message, actor: conversation.user)
      end

      expect(declined).to eq(false)
    end
  end
end

