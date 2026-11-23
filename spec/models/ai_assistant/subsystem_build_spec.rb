# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::SubsystemBuild do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }

  def build_for(conversation, **attributes)
    described_class.create!(
      customer_id: conversation.customer_id,
      conversation: conversation,
      user: conversation.user,
      blueprint: { "domain" => "Academics", "journeys" => ["create-1"] },
      **attributes
    )
  end

  it "starts running at the journeys stage with empty state" do
    build = build_for(conversation)

    expect(build).to have_attributes(
      status: "running", stage: "journeys", questions: [], answers: [], results: {}
    )
    expect(build).to be_active
    expect(build.name).to eq("Academics")
    expect(described_class.for_customer(customer.id)).to contain_exactly(build)
  end

  it "allows only one active build per conversation" do
    build_for(conversation)

    expect { build_for(conversation) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows a new build once the previous one is over" do
    build_for(conversation, status: "finished")
    build_for(conversation, status: "cancelled")

    expect(build_for(conversation)).to be_active
  end

  it "rejects an unknown status or stage" do
    build = described_class.new(
      customer_id: customer.id, conversation: conversation, user: user,
      status: "paused", stage: "deploy"
    )

    expect(build).not_to be_valid
    expect(build.errors.attribute_names).to include(:status, :stage)
  end

  it "rejects a conversation from another tenant" do
    other_customer = create(:customer)
    build = described_class.new(
      customer_id: other_customer.id, conversation: conversation, user: user
    )

    expect(build).not_to be_valid
    expect(build.errors[:conversation]).to be_present
  end

  it "treats a running build untouched past the running age as stalled" do
    build = build_for(conversation)
    expect(build).not_to be_stalled

    build.update_column(:updated_at, (described_class::MAX_RUNNING_AGE + 1.minute).ago)
    expect(build).to be_stalled
  end

  it "never treats a build waiting for answers as stalled" do
    build = build_for(conversation, status: "waiting_for_answers")
    build.update_column(:updated_at, 2.days.ago)

    expect(build).not_to be_stalled
  end
end
