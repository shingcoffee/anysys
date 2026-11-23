# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::Authentication::Users", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/modules/authentication/users" }

  it_behaves_like "an admin-guarded GET"

  it "lists member users by default" do
    member = create(:user, :member, customer: customer)
    get guard_path
    expect(response).to have_http_status(:ok)
    desktop = response.body.split('<div class="hidden sm:block', 2).last
    rows = desktop[desktop.index("<tbody")..desktop.index("</tbody>")]
    expect(rows).to include(member.email)
    expect(rows).not_to include(admin.email)
  end

  it "ignores a Role sort key because primary_role_key is not a column" do
    member = create(:user, :member, customer: customer)
    get guard_path, params: { sort: "primary_role_key", dir: "asc" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(member.email)
  end
end
