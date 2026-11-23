# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::UniformTiming do
  before do
    allow(ActiveRecord::Base.connection).to receive(:transaction_open?).and_return(false)
    allow(described_class).to receive(:sleep)
  end

  it "sleeps for whatever is left of the floor" do
    allow(described_class).to receive(:start).and_return(10.1)

    described_class.pad(10.0)

    expect(described_class).to have_received(:sleep) { |seconds| expect(seconds).to be_within(0.001).of(0.3) }
  end

  it "does not sleep once the floor has passed" do
    allow(described_class).to receive(:start).and_return(10.5)

    described_class.pad(10.0)

    expect(described_class).not_to have_received(:sleep)
  end

  it "never waits while a transaction holds locks" do
    allow(ActiveRecord::Base.connection).to receive(:transaction_open?).and_return(true)
    allow(described_class).to receive(:start).and_return(10.0)

    described_class.pad(10.0)

    expect(described_class).not_to have_received(:sleep)
  end

  it "ignores a missing start" do
    described_class.pad(nil)

    expect(described_class).not_to have_received(:sleep)
  end
end
