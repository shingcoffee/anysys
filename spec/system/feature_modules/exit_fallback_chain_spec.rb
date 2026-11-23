# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Exit fallback chain", type: :model do
  let(:customer) { create(:customer) }
  let!(:fm) do
    enable_module!("payment", customer, name: "Payments", configuration: {}.to_json)
      .tap { |mod| mod.update!(handoff_enabled: true) }
  end
  let(:cfm) { FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: fm) }
  let(:landing) { create(:page, customer: customer, launched: true) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  def resolve(session_target)
    FeatureModules::ExitResolver.call(customer: customer, module_key: "payment", session_exit_target: session_target)
  end

  it "uses the session_exit_target when provided and resolvable" do
    allow_any_instance_of(FeatureModules::Module).to receive(:registration_class).and_return(FeatureModules::Payment::Registration)

    expect(resolve("kind" => "page", "page_id" => landing.id)).to eq("/#{customer.id}/page/#{landing.public_uuid}")
  end

  it "falls back to customer override when no session target" do
    allow_any_instance_of(FeatureModules::Module).to receive(:registration_class).and_return(FeatureModules::Payment::Registration)
    cfm.update!(configuration: { exit_landing_page: { kind: "page", page_id: landing.id } }.to_json)

    expect(resolve(nil)).to eq("/#{customer.id}/page/#{landing.public_uuid}")
  end

  it "falls back to module default_exit when no session target and no customer override" do
    allow_any_instance_of(FeatureModules::Module).to receive(:registration_class).and_return(FeatureModules::Payment::Registration)

    # Payment's default_exit is kind=route, name=customer_home → /:customer_id/admin
    expect(resolve(nil)).to eq("/#{customer.id}/admin/dashboard")
  end

  it "falls back to customer home (/:customer_id/admin) when all other steps fail" do
    no_default = class_double(FeatureModules::BaseModule, default_exit_config: nil)
    allow_any_instance_of(FeatureModules::Module).to receive(:registration_class).and_return(no_default)

    expect(resolve(nil)).to eq("/#{customer.id}/admin/dashboard")
  end

  it "skips an unresolvable session_exit_target (e.g., deleted page) and falls through" do
    allow_any_instance_of(FeatureModules::Module).to receive(:registration_class).and_return(FeatureModules::Payment::Registration)

    expect(resolve("kind" => "page", "page_id" => 9_999_999)).to eq("/#{customer.id}/admin/dashboard")
  end
end
