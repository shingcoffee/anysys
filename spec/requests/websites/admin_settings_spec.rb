# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Websites::Admin::Settings", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:website_module) { enable_module!("website", customer, name: "Website") }
  let(:admin) { create(:user, :admin, customer: customer, password: "password123") }
  let(:site_path) { "/#{customer.id}/admin/settings/modules/website/site" }
  let(:skeleton_path) { "/#{customer.id}/admin/settings/modules/website/skeleton" }
  let(:guard_path) { site_path }

  before do
    Current.customer = customer
    sign_in admin
  end

  it_behaves_like "an admin-guarded request", :patch

  describe "POST skeleton replace — auth guards" do
    let(:guard_path) { skeleton_path }

    it_behaves_like "an admin-guarded request", :post
  end


  def disable_website_module!
    FeatureModules::CustomerAssignment.find_by!(
      customer: customer, feature_module: FeatureModules::Module.find_by!(key: "website")
    ).update!(status: :suspended)
  end

  def cross_tenant_blocked
    have_http_status(:not_found).or have_http_status(:forbidden).or have_http_status(:found)
  end

  describe "GET show" do
    let!(:site) { create(:website, customer: customer, name: "Studio") }

    it "renders settings sections, the theme picker, and the starter picker" do
      get "/#{customer.id}/admin/settings/modules/website"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-controller=\"website-theme-picker\"")
      expect(response.body).to include("data-theme-preview-swatch")
      expect(response.body).to include("data-skeleton-replace")
      expect(response.body).to include(I18n.t("website.admin.settings.theme.preview.headline"))
      expect(response.body).to include(I18n.t("website_settings.starter.heading"))
    end
  end

  describe "PATCH site" do
    let!(:site) { create(:website, customer: customer, name: "Studio") }

    it "publishes the tenant site from Settings / Website" do
      site.update!(published: false)

      patch site_path, params: { website: { published: true } }

      expect(response).to redirect_to(admin_settings_modules_website_path(customer.id))
      expect(flash[:notice]).to eq(I18n.t("website.admin.flash.site_saved"))
      expect(site.reload.published).to be(true)
    end

    it "does not publish another tenant's site" do
      site.update!(published: false)
      sign_in create(:user, :admin, customer: create(:customer))

      patch site_path, params: { website: { published: true } }

      expect(response).to cross_tenant_blocked
      expect(site.reload.published).to be(false)
    end

    it "persists nested footer columns from indexed params" do
      patch site_path, params: {
        website: {
          name: "Studio",
          footer: {
            blurb: "Made here.",
            columns: {
              "0" => {
                heading: "Visit",
                position: "0",
                links: {
                  "0" => { label: "About", url: "about" },
                  "1" => { label: "", url: "" }
                }
              }
            }
          }
        }
      }

      expect(response).to have_http_status(:redirect)
      expect(flash[:notice]).to eq(I18n.t("website.admin.flash.site_saved"))
      site.reload
      expect(site.footer["blurb"]).to eq("Made here.")
      expect(site.footer["columns"]).to eq(
        [ { "heading" => "Visit", "links" => [ { "label" => "About", "url" => "about" } ] } ]
      )
    end

    it "rejects a javascript: footer href with unprocessable" do
      site.update!(footer: { "blurb" => "Keep me", "columns" => [] })

      patch site_path, params: {
        website: {
          name: "Studio",
          footer: {
            columns: {
              "0" => {
                heading: "Visit",
                links: {
                  "0" => { label: "Hack", url: "javascript:alert(1)" }
                }
              }
            }
          }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("website.admin.flash.site_save_failed"))
      expect(response.body).to include("javascript:alert(1)")
      expect(site.reload.footer["blurb"]).to eq("Keep me")
      expect(Array(site.footer["columns"])).to be_empty
    end

    it "returns 404 when the Website module is disabled" do
      disable_website_module!

      patch site_path, params: { website: { name: "Studio" } }

      expect(response).to have_http_status(:not_found)
      expect(site.reload.name).to eq("Studio")
    end

    it "does not admit an admin of another customer" do
      other = create(:customer)
      sign_in create(:user, :admin, customer: other)

      patch site_path, params: {
        website: {
          name: "Hijacked",
          footer: {
            columns: {
              "0" => {
                heading: "Leak",
                links: { "0" => { label: "About", url: "about" } }
              }
            }
          }
        }
      }

      expect(response).to cross_tenant_blocked
      expect(site.reload.name).to eq("Studio")
      expect(site.footer["columns"]).to be_blank
    end
  end

  describe "POST skeleton" do
    let!(:site) { create(:website, customer: customer, skeleton_key: "presence") }

    it "lets a tenant admin replace the skeleton" do
      create(:website_page, :home, website: site, customer: customer)

      post skeleton_path, params: { skeleton_key: "cinematic" }

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(admin_modules_website_root_path(customer.id))
      expect(flash[:notice]).to eq(I18n.t("website.admin.flash.skeleton_replaced"))
      expect(site.reload.skeleton_key).to eq("cinematic")
    end

    it "does not admit an admin of another customer" do
      other = create(:customer)
      sign_in create(:user, :admin, customer: other)

      post skeleton_path, params: { skeleton_key: "cinematic" }

      expect(response).to cross_tenant_blocked
      expect(site.reload.skeleton_key).to eq("presence")
    end
  end
end
