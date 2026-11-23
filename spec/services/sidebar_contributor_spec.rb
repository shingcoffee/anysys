# frozen_string_literal: true

require "rails_helper"

RSpec.describe SidebarContributor do
  it "requires #contribute to be implemented" do
    ctx = DashboardContext.new(
      current_user: nil, current_customer: nil,
      current_menu_item: :pages, request_path: "/"
    )
    expect { described_class.new(ctx).contribute }.to raise_error(NotImplementedError)
  end

  it "defines a registry in deterministic order" do
    expect(described_class.registry).to eq([
      EntitiesContributor,
      ModulesContributor,
      SettingsContributor,
      MaintenanceContributor
    ])
  end
end
