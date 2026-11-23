# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Prompt::Sections::FlowchartHandoff do
  let(:customer) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }
  let(:context) { AiAssistant::Assistant::Prompt::Context.new(conversation: conversation, mode: :entity) }

  def render = described_class.new(context).render

  it "teaches the platform owner when to hand a turn to the flowchart pass" do
    conversation.update!(user: find_or_create_platform_owner)

    content = render

    expect(content).to start_with("## Handing a turn to the flowchart designer")
    expect(content).to include('`"flowchart": true`', "greetings, thanks, small talk and questions")
  end

  it "drops out for a tenant admin" do
    expect(render).to be_nil
  end

  # ScriptedCompletion and the e2e provider stub recognise the flowchart pass
  # by this marker in the system prompt.
  it "never names the flowchart pass's own apply intent" do
    conversation.update!(user: find_or_create_platform_owner)

    expect(render).not_to include("apply_flowchart")
  end
end
