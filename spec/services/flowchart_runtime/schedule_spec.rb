# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FlowchartRuntime::Schedule" do
  subject(:facade) { "FlowchartRuntime::Schedule".constantize }

  it "returns the next time for a valid cron expression" do
    expect(facade.next_cron_time("0 9 * * *")).to respond_to(:to_time)
  end

  it "rejects an invalid cron expression" do
    expect { facade.next_cron_time("not a cron") }.to raise_error do |error|
      expect(error.class.name).to eq("FlowchartRuntime::Schedule::Error")
      expect(error.message).to eq("invalid cron expression")
    end
  end
end
