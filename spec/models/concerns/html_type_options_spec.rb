# frozen_string_literal: true

require "rails_helper"

RSpec.describe HtmlTypeOptions do
  describe ".grouped_html_types" do
    subject(:result) { described_class.grouped_html_types }

    it "returns a Hash with all expected category keys" do
      expect(result.keys).to eq(["Text", "Selection", "Numeric", "Date & Time", "Contact", "Media & File"])
    end

    it "places type entries in the correct category buckets" do
      aggregate_failures do
        expect(result["Text"]).to include(["Text Input", "text"])
        expect(result["Text"]).to include(["Search", "search"])
        expect(result["Selection"]).to include(["Dropdown", "select"])
        expect(result["Date & Time"]).to include(["Month", "month"])
        expect(result["Date & Time"]).to include(["Week", "week"])
        expect(result["Media & File"]).to include(["Image Upload", "image"])
      end
    end
  end

  describe ".all_html_types" do
    it "returns a flat array of all HTML types" do
      result = described_class.all_html_types

      expect(result).to be_an(Array)
      expect(result).to include(["Text Input", "text"])
      expect(result).to include(["Dropdown", "select"])
      expect(result).to include(["Email", "email"])
    end

    it "includes all 21 HTML types" do
      result = described_class.all_html_types

      expect(result.length).to eq(21)
    end
  end

  describe ".valid_html_type?" do
    it "returns true for registered types and false for removed, unknown, blank, or nil values" do
      aggregate_failures do
        expect(described_class.valid_html_type?("text")).to be true
        expect(described_class.valid_html_type?("select")).to be true
        expect(described_class.valid_html_type?("email")).to be true
        expect(described_class.valid_html_type?("datetime-local")).to be true
        expect(described_class.valid_html_type?("search")).to be true
        expect(described_class.valid_html_type?("month")).to be true
        expect(described_class.valid_html_type?("week")).to be true
        expect(described_class.valid_html_type?("image")).to be true
        expect(described_class.valid_html_type?("multi-select")).to be false
        expect(described_class.valid_html_type?("switch")).to be false
        expect(described_class.valid_html_type?("currency")).to be false
        expect(described_class.valid_html_type?("rating")).to be false
        expect(described_class.valid_html_type?("rich-text")).to be false
        expect(described_class.valid_html_type?("signature")).to be false
        expect(described_class.valid_html_type?("invalid")).to be false
        expect(described_class.valid_html_type?("")).to be false
        expect(described_class.valid_html_type?(nil)).to be false
      end
    end
  end

  describe ".label_for" do
    it "returns the human label for registered types" do
      aggregate_failures do
        expect(described_class.label_for("text")).to eq("Text Input")
        expect(described_class.label_for("select")).to eq("Dropdown")
        expect(described_class.label_for("email")).to eq("Email")
        expect(described_class.label_for("datetime-local")).to eq("DateTime")
        expect(described_class.label_for("search")).to eq("Search")
        expect(described_class.label_for("month")).to eq("Month")
        expect(described_class.label_for("week")).to eq("Week")
        expect(described_class.label_for("image")).to eq("Image Upload")
      end
    end

    it "returns the value itself for unknown types and 'Text Input' for nil/blank" do
      aggregate_failures do
        expect(described_class.label_for("unknown")).to eq("unknown")
        expect(described_class.label_for(nil)).to eq("Text Input")
        expect(described_class.label_for("")).to eq("Text Input")
      end
    end
  end

  describe '.selection_type?' do
    it "returns true for selection inputs and false for non-selection inputs" do
      aggregate_failures do
        expect(described_class.selection_type?('select')).to be true
        expect(described_class.selection_type?('radio')).to be true
        expect(described_class.selection_type?('checkbox')).to be true
        expect(described_class.selection_type?('text')).to be false
        expect(described_class.selection_type?('number')).to be false
        expect(described_class.selection_type?(nil)).to be false
        expect(described_class.selection_type?('')).to be false
      end
    end
  end

  describe '.config_type_for' do
    it "maps selection-type inputs to :selection, numeric to :numeric, textarea and file variants" do
      aggregate_failures do
        expect(described_class.config_type_for('select')).to eq(:selection)
        expect(described_class.config_type_for('radio')).to eq(:selection)
        expect(described_class.config_type_for('checkbox')).to eq(:selection)
        expect(described_class.config_type_for('number')).to eq(:numeric)
        expect(described_class.config_type_for('range')).to eq(:numeric)
        expect(described_class.config_type_for('textarea')).to eq(:textarea)
        expect(described_class.config_type_for('file')).to eq(:file)
        expect(described_class.config_type_for('image')).to eq(:file)
      end
    end

    it "returns nil for plain inputs and nil/unknown values" do
      aggregate_failures do
        expect(described_class.config_type_for('text')).to be_nil
        expect(described_class.config_type_for('email')).to be_nil
        expect(described_class.config_type_for('search')).to be_nil
        expect(described_class.config_type_for('month')).to be_nil
        expect(described_class.config_type_for(nil)).to be_nil
      end
    end
  end

  describe '.configurable_type?' do
    it "returns true for types with extra config options and false for plain types" do
      aggregate_failures do
        expect(described_class.configurable_type?('select')).to be true
        expect(described_class.configurable_type?('range')).to be true
        expect(described_class.configurable_type?('textarea')).to be true
        expect(described_class.configurable_type?('file')).to be true
        expect(described_class.configurable_type?('image')).to be true
        expect(described_class.configurable_type?('text')).to be false
        expect(described_class.configurable_type?('email')).to be false
        expect(described_class.configurable_type?('search')).to be false
        expect(described_class.configurable_type?('signature')).to be false
      end
    end
  end
end
