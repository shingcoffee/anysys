# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::TestConnectionJob do
  let(:settings) { create(:ai_assistant_provider_settings) }

  it "calls TestConnection with the settings row" do
    expect(AiAssistant::Activities::TestConnection).to receive(:call).with(settings: settings)
    described_class.new.perform(settings.id)
  end

  it "is a no-op when the settings row is gone" do
    expect(AiAssistant::Activities::TestConnection).not_to receive(:call)
    expect { described_class.new.perform(-1) }.not_to raise_error
  end
end
