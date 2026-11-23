# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin full-width default", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/maintenance/constants" }

  it_behaves_like "an admin-guarded GET"

  it "renders admin index pages inside the :full width container" do
    get "/#{customer.id}/admin/maintenance/constants"
    expect(response).to have_http_status(:ok)
    # :full tier uses w-full + horizontal padding, never max-w-7xl.
    expect(response.body).to include('class="w-full px-3 sm:px-4 lg:px-8 py-8 lg:py-10"')
    expect(response.body).not_to match(/max-w-7xl[^"]*py-8 lg:py-10/)
  end

  it "returns a layoutless response when the admin-table frame requests an update" do
    get "/#{customer.id}/admin/maintenance/constants",
        headers: { "Turbo-Frame" => "admin-table" }
    expect(response).to have_http_status(:ok)
    # Layout chrome is skipped — no <body>, no sidebar, no top bar.
    expect(response.body).not_to include("<body")
    # The frame is still in the response so Turbo can swap it.
    expect(response.body).to include('<turbo-frame id="admin-table"')
  end
end
