# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Activities::Provision do
  let_it_be(:customer) { create(:customer, name: "Harbour Studio") }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  def provision
    described_class.call(customer: customer)
  end

  it "creates a website named after the customer with unpublished skeleton pages" do
    result = provision
    expect(result.success?).to be(true)

    site = result.model
    expect(site.name).to eq("Harbour Studio")
    expect(site.published).to be(false)
    expect(site.skeleton_key).to eq("presence")
    expect(site.theme).to eq(Websites::Theme.for_catalog("presence").to_stored)
    expect(site.pages.count).to eq(Websites::Skeletons.pages_for("presence").size)
    expect(site.pages.where(published: true)).to be_empty
    expect(site.pages.where(home: true).count).to eq(1)
    expect(site.home_page.slug).to eq("")
    expect(site.home_page.sections.first["props"]["eyebrow"]).to eq("Introduction")
    expect(site.home_page.sections.first["props"]["visual_url"]).to start_with("https://images.unsplash.com/")
    expect(site.home_page.sections.first["id"]).to start_with("sec_")
  end

  it "is idempotent — a second call returns the existing site without adding pages" do
    first = provision.model
    expect {
      second = provision
      expect(second.success?).to be(true)
      expect(second.model.id).to eq(first.id)
    }.not_to change { first.pages.count }
  end

  it "uses the registration configuration_schema default skeleton" do
    expect(FeatureModules::Website::Registration.configuration_schema.dig("default_skeleton_key", "default")).to eq("presence")
    expect(described_class.default_skeleton_key).to eq("presence")
  end

  it "rolls back a new site when its starter collides with an existing shortcut" do
    target = create(:page, :for_member, :for_public, customer: customer, launched: true)
    PageShortcut.create!(customer_id: customer.id, path: "/about", target: target)
    result = nil

    expect { result = provision }.not_to change(Website, :count)
    expect(result).not_to be_success
    expect(WebsitePage.where(customer_id: customer.id)).to be_empty
    expect(PageShortcut.for_customer(customer.id).find_by!(path: "/about").target_id).to eq(target.id)
  end
end
