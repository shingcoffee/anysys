# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::Website::Skeletons", type: :request do
  include_context "as platform owner"

  let(:guard_path) { "/#{customer.id}/admin/maintenance/platform/module_settings/website/skeletons" }

  before { find_or_create_feature_module!("website", name: "Website") }

  it_behaves_like "a platform-owner-guarded GET"

  it "allows the platform owner to open the skeletons gallery" do
    get guard_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("website.platform.skeletons.heading"))
  end

  it "filters the gallery by category" do
    get guard_path, params: { category: "education" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-skeleton-key="campus"')
    expect(response.body).not_to include('data-skeleton-key="presence"')
  end

  it "links every gallery card to its full-size preview" do
    get guard_path
    expect(response.body).to include("#{guard_path}/presence/preview")
  end

  describe "full-size preview" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/platform/module_settings/website/skeletons/presence/preview" }

    before { Websites::Catalog.sync! }

    it_behaves_like "a platform-owner-guarded GET"

    it "renders the home page in public chrome with a page switcher that stays inside the preview" do
      get guard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("website.platform.preview.back"))
      expect(response.body).to include("#{guard_path}?page=about")
      expect(response.body).to include('aria-current="page"')
    end

    it "switches to the requested page and falls back to home for an unknown slug" do
      about = Websites::Skeletons.seed_pages_for("presence").find { |page| page["slug"] == "about" }
      heading = about["sections"].filter_map { |section| section.dig("props", "headline").presence || section.dig("props", "heading").presence }.first

      get guard_path, params: { page: "about" }
      expect(response.body).to include(CGI.escapeHTML(heading))

      get guard_path, params: { page: "missing" }
      expect(response).to have_http_status(:ok)
    end

    it "does not persist a website or pages" do
      expect { get guard_path }.not_to change { [Website.unscoped.count, WebsitePage.unscoped.count] }
    end

    it "returns not found for an unknown skeleton" do
      get "/#{customer.id}/admin/maintenance/platform/module_settings/website/skeletons/nope/preview"
      expect(response).to have_http_status(:not_found)
    end
  end
end
