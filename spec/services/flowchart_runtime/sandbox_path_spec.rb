# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::SandboxPath do
  it "joins a basename under the generated root" do
    path = described_class.generated_path("report.csv")
    expect(path).to end_with("tmp/flowchart_generated/report.csv")
    expect(File.expand_path(path)).to start_with(File.expand_path(Rails.root.join("tmp/flowchart_generated").to_s))
  end

  it "rejects path traversal filenames" do
    expect { described_class.generated_path("../evil.txt") }.to raise_error(FlowchartRuntime::SandboxPath::Error)
    expect { described_class.generated_path("/etc/passwd") }.to raise_error(FlowchartRuntime::SandboxPath::Error)
  end
end
