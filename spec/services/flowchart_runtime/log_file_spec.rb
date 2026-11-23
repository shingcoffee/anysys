# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::LogFile do
  let(:tenant) { "81721200" }

  after do
    FileUtils.rm_rf(Rails.root.join(described_class::ROOT))
  end

  describe ".path_for" do
    it "scopes the path under the tenant directory" do
      path = described_class.path_for(tenant, "custom.log")
      expect(path).to eq(Rails.root.join(described_class::ROOT, tenant, "custom.log").to_s)
    end

    it "gives two tenants different files for the same filename" do
      expect(described_class.path_for("111", "a.log")).not_to eq(described_class.path_for("222", "a.log"))
    end

    it "discards any directory component" do
      expect(described_class.path_for(tenant, "log/nested/custom.log"))
        .to eq(Rails.root.join(described_class::ROOT, tenant, "custom.log").to_s)
    end

    it "falls back to the default filename when none is given" do
      expect(described_class.path_for(tenant, nil))
        .to end_with("/#{tenant}/#{described_class::DEFAULT_FILENAME}")
    end

    it "falls back to the default filename for a bare dot-dot" do
      expect(described_class.path_for(tenant, "..")).to end_with("/#{described_class::DEFAULT_FILENAME}")
    end

    it "fails closed without a tenant" do
      expect { described_class.path_for("", "a.log") }
        .to raise_error(described_class::Error, /tenant namespace is required/)
    end

    it "fails closed for a tenant containing a separator" do
      expect { described_class.path_for("../etc", "a.log") }
        .to raise_error(described_class::Error, /unsafe tenant namespace/)
    end

    it "fails closed for a newline-suffixed tenant" do
      expect { described_class.path_for("81\n21", "a.log") }
        .to raise_error(described_class::Error, /unsafe tenant namespace/)
    end

    it "fails closed for an unsafe filename" do
      expect { described_class.path_for(tenant, "a b.log") }
        .to raise_error(described_class::Error, /unsafe log filename/)
    end

    it "fails closed for an embedded null byte in the tenant" do
      expect { described_class.path_for("81\u000021", "a.log") }
        .to raise_error(described_class::Error, /unsafe tenant namespace/)
    end
  end

  describe ".append" do
    it "appends lines to the tenant file" do
      expect(described_class.append(tenant, "custom.log", "one")).to be(true)
      described_class.append(tenant, "custom.log", "two")

      expect(File.read(described_class.path_for(tenant, "custom.log"))).to eq("one\ntwo\n")
    end

    it "keeps two tenants' lines apart" do
      described_class.append("111", "shared.log", "from-111")
      described_class.append("222", "shared.log", "from-222")

      expect(File.read(described_class.path_for("111", "shared.log"))).to eq("from-111\n")
      expect(File.read(described_class.path_for("222", "shared.log"))).to eq("from-222\n")
    end

    it "fails closed rather than writing unscoped" do
      expect { described_class.append(nil, "custom.log", "x") }.to raise_error(described_class::Error)
    end
  end
end
