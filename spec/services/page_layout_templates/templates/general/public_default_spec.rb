# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageLayoutTemplates::Templates::General::PublicDefault do
  describe "DEFINITION" do
    subject(:definition) { described_class::DEFINITION }

    it "is frozen" do
      expect(definition).to be_frozen
    end

    it "has key public_default" do
      expect(definition[:key]).to eq("public_default")
    end

    it "has name Default (Public)" do
      expect(definition[:name]).to eq("Default (Public)")
    end

    it "is registered under the general category" do
      expect(definition[:category]).to eq("general")
    end

    it "uses the showcase theme preset" do
      expect(definition[:theme_preset]).to eq("showcase")
    end

    it "has non-empty preview_rows" do
      expect(definition[:preview_rows]).to be_an(Array)
      expect(definition[:preview_rows]).not_to be_empty
    end

    describe "layout" do
      subject(:layout) { definition[:layout] }

      it "tags the audience as public" do
        expect(layout[:audience]).to eq("public")
      end

      it "defaults to full width" do
        expect(layout[:default_width]).to eq("full")
      end

      it "opts into mobile_stack" do
        expect(layout[:mobile_stack]).to be true
      end

      it "groups by attribute_groups" do
        expect(layout[:group_by]).to eq(:attribute_groups)
      end

      it "injects spacers and dividers between sections" do
        expect(layout[:inject_elements]).to eq([
          { after_section: 0, type: "spacer" },
          { after_section: 1, type: "divider" },
          { after_section: 2, type: "divider" },
          { after_section: 3, type: "spacer" }
        ])
      end

      describe "field_width_rules" do
        subject(:rules) { layout[:field_width_rules] }

        it "covers every html_type from PageContentGenerator::HTML_TYPE_COMPONENTS" do
          expect(rules.keys).to match_array(PageContentGenerator::HTML_TYPE_COMPONENTS.keys)
        end

        it "uses only valid width values" do
          rules.each_value { |w| expect(%w[full half third two_thirds]).to include(w) }
        end

        it "uses half only for tightly-paired short inputs" do
          %w[number currency date time color].each do |t|
            expect(rules[t]).to eq("half"), "expected #{t} => half, got #{rules[t]}"
          end
        end

        it "uses full for text, email, url, tel, month, week, password, hidden (more aggressive than member default)" do
          %w[text email url tel month week password hidden].each do |t|
            expect(rules[t]).to eq("full"), "expected #{t} => full, got #{rules[t]}"
          end
        end

        it "uses full for all selection/toggle/textarea/rich/file types" do
          %w[textarea select multi-select radio checkbox switch rich-text signature
             file image search range rating datetime-local].each do |t|
            expect(rules[t]).to eq("full"), "expected #{t} => full, got #{rules[t]}"
          end
        end
      end
    end
  end

  describe "PageLayoutTemplates.find" do
    it "returns the definition by key" do
      expect(PageLayoutTemplates.find("public_default")).to eq(described_class::DEFINITION)
    end
  end

  describe "PageLayoutTemplates::Registry" do
    it "discovers the template under the general category" do
      keys = PageLayoutTemplates.for_category("general").map { |t| t[:key] }
      expect(keys).to include("public_default")
    end
  end
end
