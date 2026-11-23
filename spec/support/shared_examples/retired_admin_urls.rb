# frozen_string_literal: true

# Retired admin URLs that must keep answering with a stable 301/404 so old
# bookmarks and inbound links do not silently succeed on a different surface.

RSpec.shared_examples "a retired email admin URL" do |from:, to:|
  include_context "as admin"

  it "permanently redirects #{from} to #{to}" do
    get "/#{customer.id}/admin/modules/emails/#{from}"
    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to("/#{customer.id}/admin/modules/emails/#{to}")
  end

  it "rejects a member on #{from}" do
    sign_in create(:user, :member, customer: customer)
    get "/#{customer.id}/admin/modules/emails/#{from}"
    expect(response).to have_http_status(:redirect)
  end
end

RSpec.shared_examples "a removed admin URL" do |path_suffix|
  include_context "as admin"

  it "does not route #{path_suffix}" do
    get "/#{customer.id}#{path_suffix}"
    expect(response).to have_http_status(:not_found)
  end
end
