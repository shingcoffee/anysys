# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Prompt::Sections::Clarifying do
  let(:customer) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }
  let(:context) { AiAssistant::Assistant::Prompt::Context.new(conversation: conversation, mode: :entity) }

  def render = described_class.new(context).render

  it "renders the asking document under its heading" do
    content = render
    document = AiAssistant::Assistant::Prompt::Document.read("clarifying")

    expect(content).to start_with("## Asking questions and stating assumptions")
    expect(content).to include(document)
    expect(content).to include("ONE `questions` array")
    expect(content).to include("`assumptions`")
    expect(content).not_to include("exactly two blockers")
    expect(content).not_to include("numbered questions")
    expect(content).not_to include("entities: []")
  end
end
