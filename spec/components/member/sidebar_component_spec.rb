# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::SidebarComponent do
  it "keeps the icon catalog the member surface settings form offers" do
    expect(described_class::ICON_PATHS.keys).to include(:home, :user, :shield_check, :credit_card, :document_text)
  end
end
