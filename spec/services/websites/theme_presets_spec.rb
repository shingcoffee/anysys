# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::ThemePresets do
  it "defines a rich gallery of complete, valid themes" do
    expect(described_class.keys.size).to be >= 20

    described_class.keys.each do |key|
      tokens = described_class.tokens(key)

      expect(tokens.keys).to match_array(Websites::Theme::TOKENS)
      tokens.each { |token, value| expect(Websites::Theme::OPTIONS.fetch(token)).to include(value) }
    end
  end

  it "keeps every preset distinct" do
    expect(described_class.keys.map { |key| described_class.tokens(key) }.uniq.size).to eq(described_class.keys.size)
  end

  it "builds a theme carrying its preset key and falls back to the default" do
    expect(described_class.theme("gilded").preset_key).to eq("gilded")
    expect(described_class.theme("nope").preset_key).to eq(described_class::DEFAULT_KEY)
  end

  it "names and describes every preset in both locales" do
    %i[en zh-CN].each do |locale|
      I18n.with_locale(locale) do
        described_class.keys.each do |key|
          expect(I18n.exists?("website.themes.#{key}.name")).to be(true)
          expect(I18n.exists?("website.themes.#{key}.description")).to be(true)
        end
      end
    end
  end
end
