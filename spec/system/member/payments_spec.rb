# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member payments page", type: :system do
  # ViewComponent::TestHelpers (mixed in for type: :system in rails_helper.rb)
  # shadows RSpec::Rails::SystemExampleGroup#page with one returning a
  # Capybara::Node::Simple wrapper, which breaks `visit`. Restore the system
  # runner's session-backed page here.
  def page
    Capybara.current_session
  end

  include_context "as member"

  before do
    enable_module!("payment", customer, name: "Payments")
  end

  it "renders the empty state when the user has no payments" do
    visit "/#{customer.id}/member/payments"
    expect(page).to have_text("No payments yet")
  end
end
