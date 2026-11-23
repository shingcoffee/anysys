require "rails_helper"

RSpec.describe Admin::Settings::Modules::Authentication::RoleDetailsComponent, type: :component do
  let(:customer) { build_stubbed(:customer) }

  %w[owner admin member support].each do |key|
    it "describes the #{key} role by access scope rather than stored permission count" do
      role = build_stubbed(:role, customer: customer, key: key, system: key != "support", locked_grants: key != "support")
      allow(role).to receive_message_chain(:users, :count).and_return(2)
      render_inline(described_class.new(role: role))
      expect(page).to have_text(Admin::Settings::RolePresenter.new(role).scope)
      expect(page).to have_css("dl div", text: /Assigned users\s+2/)
      expect(page).not_to have_text("Grants configured")
      expect(page).not_to have_css(".text-mono")
    end
  end
end
