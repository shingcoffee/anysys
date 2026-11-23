# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Activities::ReplaceSkeleton do
  let_it_be(:customer) { create(:customer) }
  let(:site) { create(:website, :published, customer: customer, skeleton_key: "presence") }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  it "destroys existing pages, recreates unpublished pages, and keeps site.published" do
    create(:website_page, :home, :published, website: site, customer: customer)
    create(:website_page, :published, website: site, customer: customer, slug: "old")

    result = described_class.call(site: site, skeleton_key: "cinematic")
    expect(result.success?).to be(true)

    site.reload
    expect(site.published).to be(true)
    expect(site.skeleton_key).to eq("cinematic")
    expect(site.theme).to eq(Websites::Theme.for_catalog("cinematic").to_stored)
    expect(site.pages.count).to eq(Websites::Skeletons.pages_for("cinematic").size)
    expect(site.pages.where(published: true)).to be_empty
    expect(site.pages.where(home: true).count).to eq(1)
    expect(site.pages.map(&:slug)).not_to include("old")
  end

  it "rejects an unknown skeleton without destroying pages" do
    home = create(:website_page, :home, website: site, customer: customer)
    result = described_class.call(site: site, skeleton_key: "unknown")

    expect(result.success?).to be(false)
    expect(result.errors).to include(I18n.t("website.errors.unknown_skeleton"))
    expect(WebsitePage.find_by(id: home.id)).to eq(home)
  end

  it "rejects a clean-slug collision before deleting pages or changing site settings" do
    home = create(:website_page, :home, :published, website: site, customer: customer)
    create(:website_page, website: site, customer: customer, slug: "original-work")
    target = create(:page, :for_member, :for_public, customer: customer, launched: true)
    shortcut = PageShortcut.create!(customer_id: customer.id, path: "/about", target: target)
    originals = site.pages.pluck(:id)
    theme = site.theme.deep_dup

    result = described_class.call(site: site, skeleton_key: "presence")

    expect(result).not_to be_success
    expect(result.errors.join).to include(I18n.t("page_shortcuts.errors.shortcut_slug_taken"))
    expect(site.reload.pages.pluck(:id)).to match_array(originals)
    expect(home.reload).to be_published
    expect(site.theme).to eq(theme)
    expect(shortcut.reload.target_id).to eq(target.id)
  end

  it "rejects an imported malformed catalog before replacement" do
    Websites::Catalog.sync!
    catalog = WebsiteSkeleton.find_by!(key: "presence")
    catalog.update_column(:pages, catalog.pages.map { |page| page.merge("home" => false) })
    home = create(:website_page, :home, website: site, customer: customer)

    result = described_class.call(site: site, skeleton_key: "presence")

    expect(result).not_to be_success
    expect(result.errors.join).to include(I18n.t("website.errors.home_required"))
    expect(site.reload.pages.pluck(:id)).to eq([home.id])
  end

  it "does not replace an archived code-defined skeleton via its seed fallback" do
    Websites::Catalog.sync!
    WebsiteSkeleton.find_by!(key: "presence").update!(archived: true)
    home = create(:website_page, :home, website: site, customer: customer)

    expect(described_class.call(site: site, skeleton_key: "presence")).not_to be_success
    expect(site.reload.pages.pluck(:id)).to eq([home.id])
  end
end
