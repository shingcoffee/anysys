# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::SubsystemBuildJob do
  include ActiveJob::TestHelper

  let(:customer) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer, locale: "zh-CN") }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }
  let(:build) do
    AiAssistant::SubsystemBuild.create!(customer_id: customer.id, conversation: conversation, user: user,
                                        blueprint: { "domain" => "School" })
  end

  it "runs the build for its tenant in the user's locale" do
    without_partial_double_verification do
      expect(AiAssistant::Subsystems::Build).to receive(:call) do |build:|
        expect(build).to eq(self.build)
        expect(Current.customer).to eq(customer)
        expect(I18n.locale).to eq(:"zh-CN")
      end
    end

    described_class.new.perform(build.id)
    expect(Current.customer).to be_nil
  end

  it "does nothing for a build that is gone or no longer running" do
    build.update!(status: "cancelled")
    expect(AiAssistant::Subsystems::Build).not_to receive(:call)

    described_class.new.perform(build.id)
    described_class.new.perform(-1)
  end

  it "waits for the conversation's turn to finish before building" do
    message = create(:ai_assistant_message, customer: customer, conversation: conversation)
    AiAssistant::Assistant::GenerationLifecycle.start!(conversation: conversation, user_message: message)
    expect(AiAssistant::Subsystems::Build).not_to receive(:call)

    expect { described_class.new.perform(build.id) }.to have_enqueued_job(described_class).with(build.id)
  end

  it "does not wait on a turn whose worker is gone" do
    message = create(:ai_assistant_message, customer: customer, conversation: conversation)
    generation = AiAssistant::Assistant::GenerationLifecycle.start!(conversation: conversation, user_message: message)
    generation.update_columns(status: "running", started_at: (AiAssistant::Generation::MAX_RUNNING_AGE + 1.minute).ago)
    expect(AiAssistant::Subsystems::Build).to receive(:call)

    described_class.new.perform(build.id)
  end
end
