# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Prompt::Sections::WebsiteAuthoring do
  let(:customer) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }
  let(:context) { AiAssistant::Assistant::Prompt::Context.new(conversation: conversation, mode: :entity) }

  def render = described_class.new(context).render

  it "drops itself when the Website module is off" do
    expect(render).to be_nil
  end

  context "when the Website module is on" do
    before { enable_module!("website", customer) }

    let(:content) { render }

    it "fills the page limit from the extraction" do
      max = Websites::Assistant::Extraction::MAX_PAGES

      expect(content).to include("Build 1–#{max} pages", "At most #{max} pages per reply")
      expect(content).not_to include("{max_pages}")
    end

    it "asks website facts through one questions array rather than a numbered list" do
      expect(content).to include("ONE `questions` array")
      expect(content).to include("at most five")
      expect(content).to include("Never re-ask")
      expect(content).to include("`[Your phone number]`")
      expect(content).not_to include("numbered questions")
    end

    it "teaches placing photos by what they show" do
      expect(content).to include("`hero_split.visual_url`", "`team_grid.people[].image_url`", "`logo_cloud.items[].image_url`")
      expect(content).to include("Never invent or guess an image URL")
    end

    it "keeps revisions to full replacements of draft pages" do
      expect(content).to include("COMPLETE new `sections`", "Published pages are read-only",
                                 "Never say a page is published or live")
    end
  end
end
