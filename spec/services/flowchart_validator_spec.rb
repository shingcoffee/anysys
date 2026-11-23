# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator do
  describe "validation guard" do
    subject(:generated) { described_class.new(flowchart).generate }

    let(:entity) { create(:entity) }

    def element(id, type, label, x:, y:, properties: {})
      { "id" => id, "type" => type, "x" => x, "y" => y,
        "width" => 100, "height" => 45, "label" => label, "properties" => properties }
    end

    def flowchart_with(elements:, connections:)
      create(:flowchart, configuration: {
        "elements" => elements, "connections" => connections, "metadata" => {}
      }.to_json)
    end

    context "with a flowchart missing start element" do
      let(:flowchart) do
        flowchart_with(
          elements: [element("el_1", "process", "Process", x: 400, y: 200)],
          connections: []
        )
      end

      it "returns nil due to validation failure" do
        expect(generated).to be_nil
      end
    end

    context "with multiple start elements" do
      let(:flowchart) do
        flowchart_with(
          elements: [
            element("el_1", "start", "Start 1", x: 100, y: 100),
            element("el_2", "start", "Start 2", x: 300, y: 100),
            element("el_3", "end", "End", x: 200, y: 300)
          ],
          connections: [{ "id" => "c1", "from" => "el_1", "to" => "el_3" }]
        )
      end

      it "returns nil due to multiple start elements" do
        expect(generated).to be_nil
      end
    end

    context "with a flowchart missing end element" do
      let(:flowchart) do
        flowchart_with(
          elements: [
            element("el_1", "start", "Start", x: 100, y: 100),
            element("el_2", "process", "Process", x: 200, y: 200)
          ],
          connections: [{ "id" => "c1", "from" => "el_1", "to" => "el_2" }]
        )
      end

      it "returns nil due to missing end element" do
        expect(generated).to be_nil
      end
    end

    context "with an element that has no incoming connections" do
      let(:flowchart) do
        flowchart_with(
          elements: [
            element("el_1", "start", "Start", x: 100, y: 100),
            element("el_2", "process", "Connected Process", x: 200, y: 200),
            element("el_3", "process", "Orphan Process", x: 400, y: 200),
            element("el_4", "end", "End", x: 200, y: 300)
          ],
          connections: [
            { "id" => "c1", "from" => "el_1", "to" => "el_2" },
            { "id" => "c2", "from" => "el_2", "to" => "el_4" }
          ]
        )
      end

      it "returns nil due to disconnected element" do
        expect(generated).to be_nil
      end
    end

    context "with a valid flowchart" do
      let(:flowchart) { create(:flowchart) }

      it "generates code successfully" do
        expect(generated).to be_present
      end
    end
  end
end
