# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::ReplyEnvelope do
  def parse(text)
    described_class.parse(text)
  end

  it "accepts chat and clarify envelopes" do
    chat = parse({ intent: "chat", reply: "Hello." }.to_json)
    clarify = parse({ intent: "clarify", reply: "What should it be called?" }.to_json)

    expect(chat).to be_valid
    expect(chat).to have_attributes(intent: "chat", reply: "Hello.")
    expect(clarify).to be_valid
    expect(clarify).to have_attributes(intent: "clarify", reply: "What should it be called?")
  end

  it "tolerates fenced JSON" do
    envelope = parse("```json\n#{{ intent: "chat", reply: "Hi" }.to_json}\n```")

    expect(envelope).to be_valid
    expect(envelope.reply).to eq("Hi")
  end

  it "treats plain text as chat" do
    envelope = parse("Pages live under Maintenance.")

    expect(envelope).to be_valid
    expect(envelope).to have_attributes(intent: "chat", reply: "Pages live under Maintenance.")
  end

  it "rejects apply_entities and any other intent" do
    expect(parse({ intent: "apply_entities", reply: "Created." }.to_json)).not_to be_valid
    expect(parse({ intent: "apply_website", reply: "Built." }.to_json)).not_to be_valid
    expect(parse({ intent: "chat", reply: "  " }.to_json)).not_to be_valid
    expect(parse("{")).not_to be_valid
  end

  it "sanitizes questions and assumptions and defaults them to empty arrays" do
    questions = [
      { "prompt" => "Which stages?", "type" => "multiple", "options" => %w[Qualification Proposal], "default" => %w[Qualification] }
    ]
    envelope = parse({
      "intent" => "chat",
      "reply" => "Two lists are specific to your team.",
      "questions" => questions,
      "assumptions" => ["  Amount is in your reporting currency.  "]
    }.to_json)

    expect(envelope).to be_valid
    expect(envelope.questions).to eq(AiAssistant::Assistant::Questions.sanitize(questions))
    expect(envelope.assumptions).to eq(["Amount is in your reporting currency."])
    expect(parse({ intent: "chat", reply: "Hello." }.to_json).questions).to eq([])
    expect(parse({ intent: "chat", reply: "Hello." }.to_json).assumptions).to eq([])
  end

  it "forces intent to clarify when any question survives sanitizing" do
    envelope = parse({
      intent: "chat",
      reply: "Confirm the pipeline and I'll build Opportunity.",
      questions: [{ prompt: "Which stages?", type: "multiple", options: %w[A B] }]
    }.to_json)

    expect(envelope).to be_valid
    expect(envelope.intent).to eq("clarify")
  end

  it "fills a blank reply from the questions intro when questions are present" do
    envelope = parse({
      intent: "clarify",
      reply: "  ",
      questions: [{ prompt: "Opening hours", type: "text", default: "Mon–Sat 8:00–18:00" }]
    }.to_json)

    expect(envelope).to be_valid
    expect(envelope.reply).to eq(I18n.t("ai_assistant.assistant.questions.intro"))
  end

  it "still rejects a blank reply when there are no questions" do
    expect(parse({ intent: "clarify", reply: "" }.to_json)).not_to be_valid
    expect(parse({ intent: "chat", reply: nil }.to_json)).not_to be_valid
  end

  it "reads a flowchart hand-off only when the flag is literally true" do
    expect(parse({ intent: "chat", reply: "Designing it.", flowchart: true }.to_json).flowchart_requested).to be(true)
    expect(parse({ intent: "chat", reply: "Hello.", flowchart: "true" }.to_json).flowchart_requested).to be(false)
    expect(parse({ intent: "chat", reply: "Hello." }.to_json).flowchart_requested).to be(false)
    expect(parse("Pages live under Maintenance.").flowchart_requested).to be(false)
  end

  it "carries no questions or assumptions on a plain-text reply" do
    envelope = parse("Pages live under Maintenance.")

    expect(envelope).to be_valid
    expect(envelope.questions).to eq([])
    expect(envelope.assumptions).to eq([])
  end

  it "does not invalidate a valid envelope when questions or assumptions are malformed" do
    envelope = parse({
      intent: "chat",
      reply: "Hello.",
      questions: "nope",
      assumptions: { "a" => 1 }
    }.to_json)

    expect(envelope).to be_valid
    expect(envelope.intent).to eq("chat")
    expect(envelope.reply).to eq("Hello.")
    expect(envelope.questions).to eq([])
    expect(envelope.assumptions).to eq([])
  end
end
