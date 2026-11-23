# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::JsonPathValidator do
  describe ".safe_json_path!" do
    # ── Valid paths ──────────────────────────────────────────────────────────

    it "accepts a simple identifier" do
      expect(described_class.safe_json_path!("name")).to eq("name")
    end

    it "accepts an identifier with underscores" do
      expect(described_class.safe_json_path!("billing_address")).to eq("billing_address")
    end

    it "accepts a leading-underscore identifier" do
      expect(described_class.safe_json_path!("_private")).to eq("_private")
    end

    it "accepts a dot-separated chain" do
      expect(described_class.safe_json_path!("contact.phone_number")).to eq("contact.phone_number")
    end

    it "accepts identifiers with digits after the first character" do
      expect(described_class.safe_json_path!("field2")).to eq("field2")
    end

    # ── Injection vectors ────────────────────────────────────────────────────

    it "raises ArgumentError when path contains a single quote" do
      expect { described_class.safe_json_path!("name'") }
        .to raise_error(ArgumentError, /Unsafe JSON path rejected/)
    end

    it "raises ArgumentError when path contains closing parenthesis" do
      expect { described_class.safe_json_path!("name))") }
        .to raise_error(ArgumentError, /Unsafe JSON path rejected/)
    end

    it "raises ArgumentError for a classic OR 1=1 injection fragment" do
      expect { described_class.safe_json_path!("name')) OR 1=1 --") }
        .to raise_error(ArgumentError, /Unsafe JSON path rejected/)
    end

    it "raises ArgumentError when path contains a semicolon" do
      expect { described_class.safe_json_path!("name;DROP TABLE entity_entries") }
        .to raise_error(ArgumentError, /Unsafe JSON path rejected/)
    end

    it "raises ArgumentError when path contains a space" do
      expect { described_class.safe_json_path!("first name") }
        .to raise_error(ArgumentError, /Unsafe JSON path rejected/)
    end

    it "raises ArgumentError when path contains SQL comment markers" do
      expect { described_class.safe_json_path!("name--comment") }
        .to raise_error(ArgumentError, /Unsafe JSON path rejected/)
    end

    it "accepts identifiers starting with a digit (String#parameterize produces these for slugs like '2024_revenue')" do
      expect(described_class.safe_json_path!("2024_revenue")).to eq("2024_revenue")
    end

    it "raises ArgumentError for an empty string" do
      expect { described_class.safe_json_path!("") }
        .to raise_error(ArgumentError, /Unsafe JSON path rejected/)
    end

    it "raises ArgumentError when path contains a wildcard asterisk" do
      expect { described_class.safe_json_path!("*") }
        .to raise_error(ArgumentError, /Unsafe JSON path rejected/)
    end
  end
end
