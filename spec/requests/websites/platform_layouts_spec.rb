# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::Website::Layouts", type: :request do
  include_context "as platform owner"

  let(:guard_path) { "/#{customer.id}/admin/maintenance/platform/module_settings/website/layouts" }

  before { find_or_create_feature_module!("website", name: "Website") }

  it_behaves_like "a platform-owner-guarded GET"

  it "allows the platform owner to open the layouts gallery" do
    get guard_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("website.platform.layouts.heading"))
    expect(response.body).to include(I18n.t("website.platform.layouts.new"))
  end

  it "filters the gallery by family" do
    get guard_path, params: { family: "standalone" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-layout-key="article"')
    expect(response.body).not_to include('data-layout-key="presence_home"')
  end

  describe "full-size preview" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/platform/module_settings/website/layouts/manifesto/preview" }

    before { Websites::Catalog.sync! }

    it_behaves_like "a platform-owner-guarded GET"

    it "renders the layout with its catalog theme and an edit link, without a page switcher" do
      get guard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("We make the quiet work visible")
      expect(response.body).to include("/layouts/manifesto/edit")
      expect(response.body).to include("bg-neutral-950 text-white")
      expect(response.body).not_to include(I18n.t("website.platform.preview.pages"))
    end

    it "is linked from the gallery card" do
      get "/#{customer.id}/admin/maintenance/platform/module_settings/website/layouts"
      expect(response.body).to include(guard_path)
    end
  end
end
