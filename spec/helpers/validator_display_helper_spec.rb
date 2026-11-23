# frozen_string_literal: true

require "rails_helper"

RSpec.describe ValidatorDisplayHelper, type: :helper do
  describe "#validator_label" do
    it "returns 'Required' for presence" do
      expect(helper.validator_label("presence")).to eq("Required")
    end

    it "handles symbol input" do
      expect(helper.validator_label(:presence)).to eq("Required")
    end

    it "returns original value for unknown validator" do
      expect(helper.validator_label("custom_validator")).to eq("custom_validator")
    end
  end

  describe "#render_validator_badges" do
    it "returns dash for empty validators" do
      result = helper.render_validator_badges([])
      expect(result).to include("-")
      expect(result).to include("text-text-muted")
    end

    it "returns dash for nil validators" do
      result = helper.render_validator_badges(nil)
      expect(result).to include("-")
    end

    it "renders badges for old-format string validators" do
      result = helper.render_validator_badges(["presence", "format_email"])
      expect(result).to include("Required")
      expect(result).to include("Email")
      expect(result).to include("badge-default")
    end

    it "renders badges for new-format object validators" do
      validators = [
        { "type" => "presence" },
        { "type" => "length_in_range", "config" => { "min" => 1, "max" => 20 } }
      ]
      result = helper.render_validator_badges(validators)
      expect(result).to include("Required")
      expect(result).to include("LenRange (1-20)")
    end

    it "ignores legacy per-validator visibility keys when rendering badges" do
      validators = [
        {
          "type" => "presence",
          "visibility" => { "admin" => true, "member" => false, "public" => false }
        }
      ]
      result = helper.render_validator_badges(validators)
      expect(result).to include("Required")
      expect(result).not_to include("Required (")
      expect(result).to include('title="presence"')
    end

    it "handles single validator as non-array" do
      result = helper.render_validator_badges("presence")
      expect(result).to include("Required")
    end

    it "renders to_s for non-String non-Hash validator entries" do
      # The else branch: v is neither a String nor a Hash-with-type
      result = helper.render_validator_badges([ 42 ])
      expect(result).to include("42")
    end

    it "wraps badges with a multiline overflow tooltip when truncate: true" do
      result = helper.render_validator_badges(["presence", "format_email"], truncate: true)
      expect(result).to include('data-tooltip="Required')
      expect(result).to include("data-tooltip-multiline=\"true\"")
      expect(result).to include("data-tooltip-overflow=\"true\"")
      expect(result).to include("max-w-[9rem]")
      expect(result).to include("flex-nowrap")
      expect(result).not_to include('title="presence"')
    end
  end

  describe "#validator_badge_display_label" do
    it "formats string, hash, and other validators" do
      expect(helper.validator_badge_display_label("presence")).to eq("Required")
      expect(helper.validator_badge_display_label({ "type" => "presence" })).to eq("Required")
      expect(helper.validator_badge_display_label(42)).to eq("42")
    end
  end
end
