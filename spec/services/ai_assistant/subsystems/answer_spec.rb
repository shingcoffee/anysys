# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Subsystems::Answer do
  include ActiveJob::TestHelper

  let(:customer) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }
  let(:message) { create(:ai_assistant_message, customer: customer, conversation: conversation, role: "user", body: "Use #general") }
  let(:questions) { [{ "id" => "q1", "prompt" => "Which channel?", "type" => "text", "options" => [], "default" => nil }] }

  def build_with(**attributes)
    AiAssistant::SubsystemBuild.create!(customer_id: customer.id, conversation: conversation, user: user,
                                        blueprint: { "domain" => "School" }, **attributes)
  end

  def consume = described_class.consume(conversation: conversation, user_message: message)

  it "leaves a conversation without an active build to the assistant" do
    build_with(status: "finished")

    expect(consume).to be_nil
  end

  it "takes the message as the answers of a waiting build and resumes it" do
    build = build_with(status: "waiting_for_answers", stage: "processing", questions: questions)
    turn = nil

    expect { turn = consume }.to have_enqueued_job(AiAssistant::SubsystemBuildJob).with(build.id)

    expect(build.reload).to have_attributes(status: "running", stage: "processing", questions: [],
                                            answers: [{ "message_id" => message.id, "questions" => questions }])
    expect(turn.body).to eq(I18n.t("ai_assistant.subsystems.answers.received", name: "School"))
    expect(turn.status).to eq("complete")
    expect(turn.effects).to eq([{ kind: "subsystem_build", action: "resumed", record: build }])
  end

  it "answers a message sent while the build runs without resuming it again" do
    build = build_with(status: "running")
    turn = nil

    expect { turn = consume }.not_to have_enqueued_job(AiAssistant::SubsystemBuildJob)

    expect(turn.body).to eq(I18n.t("ai_assistant.subsystems.answers.running", name: "School"))
    expect(build.reload.status).to eq("running")
  end

  it "fails a stalled build and leaves the message to the assistant" do
    build = build_with(status: "running")
    build.update_column(:updated_at, (AiAssistant::SubsystemBuild::MAX_RUNNING_AGE + 1.minute).ago)

    expect(consume).to be_nil
    expect(build.reload).to have_attributes(status: "failed")
    expect(build.results).to include("error" => "stalled")
  end

  it "never routes another conversation's build" do
    other = create(:ai_assistant_conversation, customer: customer, user: user)
    AiAssistant::SubsystemBuild.create!(customer_id: customer.id, conversation: other, user: user, status: "waiting_for_answers")

    expect(consume).to be_nil
  end
end
