# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator::HeaderBuilder do
  def stub_flowchart(name:, id: 14)
    instance_double("Flowchart", name: name, id: id)
  end

  def stub_entity(name:)
    instance_double("Entity", name: name, display_label: name)
  end

  let(:flowchart) { stub_flowchart(name: "Flow") }
  let(:default_header_args) do
    {
      flowchart: flowchart,
      elements: [],
      bound_entity: nil
    }
  end

  def build_header(**overrides)
    described_class.new(**default_header_args.merge(overrides))
  end

  describe "plain header" do
    subject(:builder) { build_header }

    let(:flowchart) { stub_flowchart(name: "My Blueprint Flow") }

    it "includes the frozen_string_literal comment" do
      expect(builder.build).to start_with("# frozen_string_literal: true")
    end

    it "includes the regenerate instruction with the flowchart id and name" do
      expect(builder.build).to include(
        '# Generated from flowchart #14 "My Blueprint Flow". Do not edit; regenerate it from the flowchart editor.'
      )
    end

    it "states the submitting page supplies the entity at runtime" do
      expect(builder.build).to include("# Bound entity: supplied at runtime by the submitting page")
    end

    it "omits Trigger, Multi-source, Model class and Contract class lines" do
      header = builder.build
      expect(header).not_to include("Trigger:")
      expect(header).not_to include("Multi-source:")
      expect(header).not_to include("Model class:")
      expect(header).not_to include("Contract class:")
    end
  end

  describe "unsaved flowchart" do
    let(:flowchart) { stub_flowchart(name: "Draft", id: nil) }

    it "omits the #<id> token" do
      expect(build_header.build).to include(
        '# Generated from flowchart "Draft". Do not edit; regenerate it from the flowchart editor.'
      )
      expect(build_header.build).not_to include("flowchart #")
    end
  end

  describe "bound-entity header" do
    subject(:builder) do
      build_header(bound_entity: stub_entity(name: "User Profile"))
    end

    let(:flowchart) { stub_flowchart(name: "Registration Flow") }

    it "includes the checked-against entity name and no model/contract lines" do
      header = builder.build
      expect(header).to include("# Checked against entity: User Profile")
      expect(header).not_to include("# Bound entity: supplied at runtime")
      expect(header).not_to include("Model class:")
      expect(header).not_to include("Contract class:")
      expect(header).not_to include("Blueprint")
    end
  end

  describe "subprocess list" do
    let(:flowchart) { stub_flowchart(name: "Parent Flow") }
    let(:steps_with_subprocess) do
      [
        { subprocess: { activity_class_name: "ChildActivity", subflow_name: "child_flow", flowchart_id: 5 } },
        { subprocess: { activity_class_name: "AnotherActivity", subflow_name: "another", flowchart_id: 6 } }
      ]
    end

    it "lists each subflow on one Subflows line" do
      result = build_header.build(steps_with_subprocess)
      expect(result).to include('# Subflows: ChildActivity (#5 "child_flow"), AnotherActivity (#6 "another")')
      expect(result).not_to include("# Subprocesses:")
    end

    it "omits Subflows when there are none" do
      expect(build_header.build([{ name: :do_work }])).not_to include("# Subflows:")
      expect(build_header.build([])).not_to include("# Subflows:")
    end

    it "sanitizes the activity class name token" do
      header = build_header.build([
        { subprocess: { activity_class_name: "Child\nclass Injected; end", subflow_name: "child", flowchart_id: 5 } }
      ])
      expect(header).not_to include("\nclass Injected")
      expect(header.lines).to all(match(/\A#/))
    end
  end

  describe "constructor surface" do
    it "does not accept unused model/contract/name_deriver kwargs" do
      expect {
        described_class.new(
          flowchart: flowchart,
          elements: [],
          bound_entity: nil,
          shared_flowchart: false,
          model_class_name: "X",
          contract_class_name: "Y",
          name_deriver: instance_double("ActivityGenerator::NameDeriver")
        )
      }.to raise_error(ArgumentError)
    end
  end

  describe "hostile subflow ids" do
    [
      "14\nclass InjectedHeader; end\n#",
      "14\n\#{Kernel.exit}\n#",
      "14\n__END__\n#",
      "14\u2028class InjectedHeader; end\u2028#",
      "14\u2029class InjectedHeader; end\u2029#"
    ].each do |hostile_id|
      it "does not emit an extra source line for #{hostile_id.inspect}" do
        header = build_header.build([
          { subprocess: { activity_class_name: "ChildActivity", subflow_name: "child_flow", flowchart_id: hostile_id } }
        ])
        expect(header).not_to include("class InjectedHeader")
        expect(header).not_to include("__END__")
        expect(header).not_to include("Kernel.exit")
        expect(header.lines.count { |line| !line.start_with?("#") && line.strip != "" }).to eq(0)
        expect(header).to match(/# Subflows: ChildActivity \(#14 "/)
      end
    end
  end

  describe "hostile parent flowchart id" do
    let(:flowchart) { stub_flowchart(name: "Parent", id: "9\nclass ParentId; end\n#") }

    it "keeps the generated-from line a single comment" do
      header = build_header.build

      expect(header).not_to include("class ParentId")
      expect(header.lines.count { |line| !line.start_with?("#") && line.strip != "" }).to eq(0)
      expect(header).to include(%(# Generated from flowchart #9 "Parent".))
    end
  end

  describe "safe_comment_text stripping" do
    def builder_for_name(name)
      build_header(flowchart: stub_flowchart(name: name))
    end

    it "strips newline characters to prevent comment injection" do
      header = builder_for_name("Evil\n# injected comment").build
      expect(header).not_to include("\n# injected comment")
      expect(header).to include("Evil")
    end

    it "strips carriage return, tab and null bytes" do
      expect(builder_for_name("Evil\r# injected").build).not_to include("\r# injected")
      expect(builder_for_name("Tab\there").build).not_to include("\t")
      expect(builder_for_name("Null\x00Byte").build).not_to include("\x00")
    end

    it "truncates names longer than 200 characters" do
      expect(builder_for_name("A" * 250).build).to include("#{"A" * 197}...")
    end

    it "does not truncate names of exactly 200 characters" do
      expect(builder_for_name("B" * 200).build).to include("B" * 200)
    end

    it "converts nil name to an empty quoted name" do
      expect(builder_for_name(nil).build).to include('# Generated from flowchart #14 "".')
    end
  end
end
