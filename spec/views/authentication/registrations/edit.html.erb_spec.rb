# frozen_string_literal: true

require "rails_helper"

RSpec.describe "authentication/registrations/edit.html.erb", type: :view do
  let(:customer) { create(:customer) }
  let(:resource) { create(:user, :admin, customer: customer) }

  before do
    stub_devise_view_context(resource, customer)
  end

  context "when the user has a password" do
    before { render }

    it "renders the edit title" do
      expect(rendered).to include("Edit your profile")
    end

    it "posts PATCH/PUT to the user_registration path" do
      expect(rendered).to include("action=\"/auth\"")
      expect(rendered).to match(/name="_method"\s+value="put"/)
    end

    it "renders all profile and password-change inputs including current_password" do
      %w[first_name last_name email password password_confirmation current_password].each do |field|
        expect(rendered).to match(/name="user\[#{field}\]"/)
      end
    end

    # Resolved in the template through Authentication::LandingPath rather than
    # the controller's Devise `after_update_path_for` hook. Exposing that hook
    # as a helper_method coupled the view to the controller and put this whole
    # spec file permanently in the red, since a view spec has no such helper.
    it "renders the Cancel link back to the admin surface for an admin" do
      expect(rendered).to include("Cancel")
      expect(rendered).to include(admin_assistant_path(customer.id))
    end
  end

  context "when the user is a member" do
    let(:resource) { create(:user, :member, customer: customer) }

    before { render }

    it "renders the Cancel link back to the member surface" do
      expect(rendered).to include(member_dashboard_path(customer.id))
      expect(rendered).not_to include(admin_assistant_path(customer.id))
    end
  end

  context "when the user has not set a password" do
    before do
      resource.encrypted_password = ""
      render
    end

    it "hides current_password" do
      expect(rendered).not_to match(/name="user\[current_password\]"/)
      expect(rendered).to include(I18n.t("auth.registrations.edit.set_password_hint"))
    end
  end
end
