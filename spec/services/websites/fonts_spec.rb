# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Fonts do
  it "builds a quoted family stack with its fallback" do
    expect(described_class.stack("playfair")).to start_with("'Playfair Display', ")
  end

  it "labels every family through I18n in both locales" do
    expect(described_class.label("plex_mono")).to eq("IBM Plex Mono")
    described_class.keys.each do |key|
      %i[en zh-CN].each { |locale| expect(I18n.t("website.fonts.#{key}", locale: locale, raise: true)).to be_present }
    end
  end

  it "covers every family a theme pairing uses" do
    families = Websites::Theme::PAIRINGS.values.flat_map { |pair| pair.values_at(:heading, :body, :accent) }

    expect(families - described_class.keys).to be_empty
  end

  it "builds one Bunny Fonts stylesheet for the requested families" do
    url = described_class.stylesheet_url(%w[inter jost inter unknown])

    expect(url).to start_with("https://fonts.bunny.net/css?family=")
    expect(url.scan("inter:").size).to eq(1)
    expect(url).to include("|jost:")
    expect(described_class.stylesheet_url([])).to be_nil
  end

  it "rejects unknown keys" do
    expect(described_class.known?("comic_sans")).to be(false)
  end
end
