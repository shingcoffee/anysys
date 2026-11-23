# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::CacheKey do
  describe ".scoped" do
    it "joins the tenant and remaining parts under the flowchart prefix" do
      expect(described_class.scoped("81721200", "breaker", "payments"))
        .to eq("flowchart:81721200:breaker:payments")
    end

    it "keeps the two-argument form used by existing cache steps" do
      expect(described_class.scoped("81721200", "user_data"))
        .to eq("flowchart:81721200:user_data")
    end

    it "inserts an optional user namespace between tenant and key" do
      expect(described_class.scoped("81721200", "user_data", namespace: "reports"))
        .to eq("flowchart:81721200:reports:user_data")
    end

    it "appends an optional version suffix" do
      expect(described_class.scoped("81721200", "user_data", version: "v2"))
        .to eq("flowchart:81721200:user_data:v2")
    end

    it "rejects a blank tenant namespace so keys can never be shared" do
      expect { described_class.scoped("", "user_data") }
        .to raise_error(described_class::Error, /tenant/)
    end

    it "rejects a blank key" do
      expect { described_class.scoped("81721200", "  ") }
        .to raise_error(described_class::Error, /key/)
    end

    it "rejects wildcard parts so a key cannot become a cache pattern" do
      expect { described_class.scoped("81721200", "user*") }
        .to raise_error(described_class::Error, /wildcard/)
    end

    it "rejects a part longer than 200 bytes" do
      expect { described_class.scoped("81721200", "x" * 201) }
        .to raise_error(described_class::Error, /length/)
    end
  end
end
