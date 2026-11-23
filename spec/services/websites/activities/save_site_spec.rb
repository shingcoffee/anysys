# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Activities::SaveSite do
  let_it_be(:customer) { create(:customer) }
  let(:site) { create(:website, customer: customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  it "persists identity, theme, seo, footer, and published" do
    result = described_class.call(
      site: site,
      params: {
        name: "North Studio",
        tagline: "Work that lasts",
        published: "1",
        theme: { appearance: "dark", accent: "gold", type: "serif", density: "compact" },
        seo: { title: "North", description: "A studio site" },
        footer: { blurb: "Made here.", columns: [ { heading: "Visit", links: [ { label: "About", url: "about" } ] } ] }
      }
    )

    expect(result.success?).to be(true)
    site.reload
    expect(site.name).to eq("North Studio")
    expect(site.tagline).to eq("Work that lasts")
    expect(site.published).to be(true)
    expect(site.theme["accent"]).to eq("gold")
    expect(site.seo["title"]).to eq("North")
    expect(site.footer["blurb"]).to eq("Made here.")
  end

  it "keeps indexed footer columns attached to the matching heading and honors position" do
    result = described_class.call(
      site: site,
      params: {
        name: site.name,
        footer: {
          blurb: "Hi",
          columns: {
            "1" => {
              "heading" => "Second",
              "position" => "0",
              "links" => { "0" => { "label" => "Team", "url" => "team" } }
            },
            "0" => {
              "heading" => "First",
              "position" => "1",
              "links" => { "0" => { "label" => "About", "url" => "about" } }
            }
          }
        }
      }
    )

    expect(result.success?).to be(true)
    columns = site.reload.footer["columns"]
    expect(columns.map { |column| column["heading"] }).to eq(%w[Second First])
    expect(columns.first["links"].first["label"]).to eq("Team")
    expect(columns.last["links"].first["url"]).to eq("about")
  end

  it "rejects a javascript: footer href" do
    result = described_class.call(
      site: site,
      params: {
        name: site.name,
        footer: { columns: [ { heading: "X", links: [ { label: "bad", url: "javascript:alert(1)" } ] } ] }
      }
    )
    expect(result.success?).to be(false)
    expect(result.errors.join).to include(I18n.t("website.errors.javascript_href"))
  end
end
