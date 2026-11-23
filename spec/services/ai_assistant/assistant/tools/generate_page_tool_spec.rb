# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Tools::GeneratePageTool do
  it "describes an admin-only generate without hierarchical visibility" do
    session = instance_double(AiAssistant::Assistant::Tools::Session)
    tool = described_class.new(session: session)

    expect(tool.description).to include("Admin-only")
    expect(tool.description).not_to match(/\bvisibility\b/)
  end
end
