# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartVersion do
  let(:flowchart) { create(:flowchart) }

  # A distinct, structurally-valid configuration payload per seed, so that
  # each commit produces a different content hash (avoids the no-op guard in
  # Versionable#commit_version!).
  def distinct_configuration(seed)
    {
      "elements" => [
        { "id" => "el_#{seed}", "type" => "start", "x" => seed, "y" => seed,
          "width" => 10, "height" => 10, "label" => "L#{seed}", "properties" => {} }
      ],
      "connections" => [],
      "metadata" => { "canvas" => { "width" => 1200, "height" => 800 }, "created_at" => Time.current.iso8601 }
    }.to_json
  end

  def content_for(payload)
    FlowchartConfigurationContent.store!(customer_id: flowchart.customer_id, payload: payload)
  end

  describe "associations" do
    it "belongs to a flowchart" do
      version = described_class.new(flowchart: flowchart, version_number: 5,
                                     content: content_for({ "k" => 1 }), customer_id: flowchart.customer_id)
      expect(version.flowchart).to eq(flowchart)
    end

    it "belongs to a content row and exposes payload through it" do
      content = content_for({ "k" => 2 })
      version = described_class.new(flowchart: flowchart, version_number: 6,
                                     content: content, customer_id: flowchart.customer_id)
      expect(version.content).to eq(content)
      expect(version.payload).to eq(content.payload)
    end
  end

  describe "validations" do
    it "requires content" do
      version = described_class.new(flowchart: flowchart, version_number: 5, customer_id: flowchart.customer_id)
      expect(version).not_to be_valid
      expect(version.errors[:content]).to be_present
    end

    it "requires version_number" do
      version = described_class.new(flowchart: flowchart, content: content_for({ "k" => 3 }),
                                     customer_id: flowchart.customer_id)
      expect(version).not_to be_valid
      expect(version.errors[:version_number]).to include("can't be blank")
    end

    it "enforces unique version_number within a flowchart" do
      duplicate = flowchart.flowchart_versions.build(
        customer_id: flowchart.customer_id,
        version_number: flowchart.current_version.version_number,
        content: content_for({ "k" => 4 }))
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:version_number]).to include("has already been taken")
    end

    it "allows the same version_number across different flowcharts" do
      other_flowchart = create(:flowchart)
      expect(flowchart.current_version.version_number).to eq(1)
      expect(other_flowchart.current_version.version_number).to eq(1)
    end
  end

  describe "scopes" do
    before do
      3.times do |i|
        flowchart.configuration = distinct_configuration(i)
        flowchart.commit_version!
      end
    end

    describe ".ordered" do
      it "orders by version_number descending" do
        versions = flowchart.flowchart_versions.ordered
        expect(versions.pluck(:version_number)).to eq([4, 3, 2, 1])
      end
    end

    describe ".recent" do
      it "returns at most 50 versions ordered descending" do
        versions = flowchart.flowchart_versions.recent
        expect(versions.pluck(:version_number)).to eq([4, 3, 2, 1])
      end
    end
  end

  describe "version creation via commit_version! (auto-committed on save)" do
    it "creates v1 automatically when the flowchart is created" do
      expect(flowchart.flowchart_versions.count).to eq(1)
      expect(flowchart.flowchart_versions.first.version_number).to eq(1)
    end

    it "stores the current configuration in the version's content" do
      version = flowchart.current_version
      expect(JSON.parse(version.payload)).to eq(JSON.parse(flowchart.configuration))
    end

    it "stores the customer_id" do
      version = flowchart.current_version
      expect(version.customer_id).to eq(flowchart.customer_id)
    end

    it "stores the description passed to commit_version!" do
      flowchart.configuration = distinct_configuration(99)
      version = flowchart.commit_version!(description: "Manual save")
      expect(version.description).to eq("Manual save")
    end

    it "no-ops (creates no new version) when the definition is unchanged" do
      expect { flowchart.commit_version! }.not_to change { flowchart.flowchart_versions.count }
    end

    it "increments version numbers as the configuration changes" do
      flowchart.configuration = distinct_configuration(1)
      flowchart.commit_version!
      flowchart.configuration = distinct_configuration(2)
      flowchart.commit_version!
      expect(flowchart.flowchart_versions.pluck(:version_number)).to contain_exactly(1, 2, 3)
    end
  end

  describe "pruning past MAX_VERSIONS" do
    it "prunes the oldest versions once the head advances past the configured limit" do
      stub_const("Versionable::MAX_VERSIONS", 2)
      flowchart.configuration = distinct_configuration(1)
      flowchart.commit_version!
      flowchart.configuration = distinct_configuration(2)
      flowchart.commit_version!

      expect(flowchart.flowchart_versions.count).to eq(2)
      expect(flowchart.flowchart_versions.minimum(:version_number)).to eq(2)
      expect(flowchart.flowchart_versions.maximum(:version_number)).to eq(3)
    end
  end

  describe "dependent destroy" do
    it "destroys versions when flowchart is destroyed" do
      3.times do |i|
        flowchart.configuration = distinct_configuration(i)
        flowchart.commit_version!
      end
      expect(flowchart.flowchart_versions.count).to eq(4)
      expect { flowchart.destroy }.to change(described_class, :count).by(-4)
    end
  end
end
