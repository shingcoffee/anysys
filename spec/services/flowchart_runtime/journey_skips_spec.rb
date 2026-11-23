# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::JourneySkips do
  let(:journey) { { "key" => "order", "step" => "start", "finishing" => false } }

  it "parks valid step keys on the submission outcome, keeping what is already there" do
    ctx = { journey: journey, submission_outcome: { message: "Saved", "journey" => { "skip" => ["notes"] } } }

    expect(described_class.request(ctx, steps: [" catering ", "notes", "Bad Key", "", nil])).to be(true)
    expect(ctx[:submission_outcome]).to eq("message" => "Saved", "journey" => { "skip" => %w[notes catering] })
  end

  it "starts an outcome when there is none" do
    ctx = { journey: journey }
    described_class.request(ctx, steps: %w[catering])

    expect(ctx[:submission_outcome]).to eq("journey" => { "skip" => %w[catering] })
  end

  it "does nothing outside a journey or without a valid key" do
    outside = {}
    described_class.request(outside, steps: %w[catering])
    expect(outside).to eq({})

    empty = { journey: journey }
    expect(described_class.request(empty, steps: ["Bad Key"])).to be(true)
    expect(empty).not_to have_key(:submission_outcome)
  end

  it "replaces a malformed journey outcome" do
    ctx = { journey: journey, submission_outcome: { "journey" => "x" } }
    described_class.request(ctx, steps: %w[catering])

    expect(ctx[:submission_outcome]).to eq("journey" => { "skip" => %w[catering] })
  end
end
