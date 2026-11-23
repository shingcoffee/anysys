# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Catalog do
  before { described_class.sync! }

  it "seeds a row for every skeleton and every skeleton page layout" do
    expect(WebsiteSkeleton.pluck(:key)).to include(*Websites::Skeletons.keys)
    expect(WebsiteLayout.pluck(:key)).to include("lumen_home", "supper_menu", "launch", "process")
    expect(WebsiteLayout.pluck(:key)).to include("voltage_home", "atrium_visit", "showcase", "compare", "newsroom", "listings", "stores", "heritage", "conference")
    expect(WebsiteLayout.pluck(:key)).to include("canvas_home", "harbor_features", "calm_practice", "marque_models", "tempo_listen", "quarterly_stories", "spotlight", "campaign", "tour", "impact", "why_us", "launch_note")
    expect(WebsiteSkeleton.find_by(key: "voyage").name).to eq("Voyage")
  end

  it "seeds every extra layout as valid sections with names in both locales" do
    described_class::EXTRA_LAYOUTS.each do |spec|
      %i[en zh-CN].each { |locale| expect(I18n.exists?("website.layouts.#{spec["key"]}.name", locale)).to be(true), "#{locale} #{spec["key"]}" }
      spec["sections"].each do |section|
        form = Websites::Contracts::Section.new(OpenStruct.new)
        expect(form.validate(section.merge("id" => "sec_1"))).to be(true), "#{spec["key"]} #{section["type"]}: #{form.errors.full_messages}"
      end
    end
  end

  it "keeps owner edits on sync but restores the code seed on refresh" do
    skeleton = WebsiteSkeleton.find_by(key: "lumen")
    layout = WebsiteLayout.find_by(key: "lumen_home")
    skeleton.update!(name: "Owner copy")
    layout.update!(name: "Owner layout", sections: layout.sections.first(1))

    described_class.sync!
    expect(skeleton.reload.name).to eq("Owner copy")
    expect(layout.reload.sections.size).to eq(1)

    described_class.refresh!
    expect(skeleton.reload.name).to eq("Lumen")
    expect(layout.reload.name).to eq("Lumen home")
    expect(layout.sections.map { |section| section["type"] }).to eq(
      Websites::Skeletons.seed_pages_for("lumen").find { |page| page["layout_key"] == "lumen_home" }["sections"].map { |section| section["type"] }
    )
  end
end
