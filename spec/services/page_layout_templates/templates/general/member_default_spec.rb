# spec/services/page_layout_templates/templates/general/member_default_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageLayoutTemplates::Templates::General::MemberDefault do
  describe "DEFINITION" do
    subject(:definition) { described_class::DEFINITION }

    it "is frozen" do
      expect(definition).to be_frozen
    end

    it "has key member_default" do
      expect(definition[:key]).to eq("member_default")
    end

    it "has name Default (Member)" do
      expect(definition[:name]).to eq("Default (Member)")
    end

    it "is registered under the general category" do
      expect(definition[:category]).to eq("general")
    end

    it "uses the modern theme preset" do
      expect(definition[:theme_preset]).to eq("modern")
    end

    it "has non-empty preview_rows" do
      expect(definition[:preview_rows]).to be_an(Array)
      expect(definition[:preview_rows]).not_to be_empty
    end

    describe "layout" do
      subject(:layout) { definition[:layout] }

      it "tags the audience as member" do
        expect(layout[:audience]).to eq("member")
      end

      it "defaults to full width (mobile-first)" do
        expect(layout[:default_width]).to eq("full")
      end

      it "groups by attribute_groups" do
        expect(layout[:group_by]).to eq(:attribute_groups)
      end

      it "has empty sections and inject_elements" do
        expect(layout[:sections]).to eq([])
        expect(layout[:inject_elements]).to eq([])
      end

      describe "field_width_rules" do
        subject(:rules) { layout[:field_width_rules] }

        it "covers every html_type from PageContentGenerator::HTML_TYPE_COMPONENTS" do
          expect(rules.keys).to match_array(PageContentGenerator::HTML_TYPE_COMPONENTS.keys)
        end

        it "uses only valid width values" do
          rules.each_value { |w| expect(%w[full half third two_thirds]).to include(w) }
        end

        it "prefers half for tightly-paired short inputs" do
          %w[text number currency date time tel month week color hidden].each do |t|
            expect(rules[t]).to eq("half"), "expected #{t} => half, got #{rules[t]}"
          end
        end

        it "uses full for selection/toggle/textarea/rich/file/email/url types" do
          %w[textarea select multi-select radio checkbox switch rich-text signature
             file image email url password search range rating datetime-local].each do |t|
            expect(rules[t]).to eq("full"), "expected #{t} => full, got #{rules[t]}"
          end
        end
      end
    end
  end

  describe "PageLayoutTemplates.find" do
    it "returns the definition by key" do
      template = PageLayoutTemplates.find("member_default")
      expect(template).to eq(described_class::DEFINITION)
    end
  end

  describe "PageLayoutTemplates::Registry" do
    it "discovers the template under the general category" do
      keys = PageLayoutTemplates.for_category("general").map { |t| t[:key] }
      expect(keys).to include("member_default")
    end
  end
end
