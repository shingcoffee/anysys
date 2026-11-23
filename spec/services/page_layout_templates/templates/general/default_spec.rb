# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageLayoutTemplates::Templates::General::Default do
  describe "DEFINITION" do
    subject(:definition) { described_class::DEFINITION }

    it "is frozen" do
      expect(definition).to be_frozen
    end

    it "has the correct key" do
      expect(definition[:key]).to eq("default")
    end

    it "has a name" do
      expect(definition[:name]).to eq("Default")
    end

    it "has a category" do
      expect(definition[:category]).to eq("general")
    end

    it "has theme_preset set to modern" do
      expect(definition[:theme_preset]).to eq("modern")
    end

    it "has non-empty preview_rows" do
      expect(definition[:preview_rows]).to be_an(Array)
      expect(definition[:preview_rows]).not_to be_empty
    end

    describe "layout" do
      subject(:layout) { definition[:layout] }

      it "has default_width set to half" do
        expect(layout[:default_width]).to eq("half")
      end

      it "has group_by set to attribute_groups (with automatic source-based fallback)" do
        expect(layout[:group_by]).to eq(:attribute_groups)
      end

      it "has empty sections array" do
        expect(layout[:sections]).to eq([])
      end

      it "has empty inject_elements array" do
        expect(layout[:inject_elements]).to eq([])
      end

      describe "field_width_rules" do
        subject(:rules) { layout[:field_width_rules] }

        it "covers all html_types from PageContentGenerator::HTML_TYPE_COMPONENTS" do
          expected_keys = PageContentGenerator::HTML_TYPE_COMPONENTS.keys
          expect(rules.keys).to match_array(expected_keys)
        end

        it "uses only valid width values" do
          valid_widths = %w[full half third two_thirds]
          rules.each_value do |width|
            expect(valid_widths).to include(width),
              "Found invalid width '#{width}'"
          end
        end

        it "maps text to half" do
          expect(rules["text"]).to eq("half")
        end

        it "maps textarea to full" do
          expect(rules["textarea"]).to eq("full")
        end

        it "maps file to full" do
          expect(rules["file"]).to eq("full")
        end

        it "maps rating to third" do
          expect(rules["rating"]).to eq("third")
        end

        it "maps checkbox to full" do
          expect(rules["checkbox"]).to eq("full")
        end
      end
    end
  end

  describe "PageLayoutTemplates.find" do
    it "returns the default template definition" do
      template = PageLayoutTemplates.find("default")
      expect(template).to eq(described_class::DEFINITION)
    end
  end
end
