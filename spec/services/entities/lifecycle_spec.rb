# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::Lifecycle do
  let(:customer) { create(:customer) }
  let(:options) do
    [
      { "label" => "Draft", "value" => "draft", "default" => true },
      { "label" => "Submitted", "value" => "submitted" },
      { "label" => "Approved", "value" => "approved" },
      { "label" => "Rejected", "value" => "rejected" }
    ]
  end
  let(:transitions) do
    [
      { "from" => "draft", "to" => "submitted", "by" => %w[member] },
      { "from" => "submitted", "to" => "approved", "by" => %w[admin] },
      { "from" => "submitted", "to" => "rejected", "by" => %w[admin system] }
    ]
  end
  let(:status) do
    { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "select",
      "config" => { "source" => "manual", "options" => options },
      "lifecycle" => { "transitions" => transitions } }
  end
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" },
      status
    ].to_json)
  end

  def new_entry(data = {})
    EntityEntry.build_for(entity).new(entity: entity, customer_id: customer.id).tap { |entry| data.each { |slug, value| entry.public_send("#{slug}=", value) } }
  end

  def saved_entry(data)
    entry = new_entry(data).tap(&:save!)
    EntityEntry.build_for(entity).find(entry.id)
  end

  def violations(entry, audience)
    described_class.violations(entry, audience: audience)
  end

  describe ".from_attribute" do
    it "reads the states, initial state and transitions of a select with static options" do
      lifecycle = described_class.from_attribute(status)

      expect(lifecycle).to have_attributes(slug: "status", initial: "draft", states: %w[draft submitted approved rejected])
      expect(lifecycle.transitions.map { |t| [t.from, t.to, t.by] }).to eq([
        ["draft", "submitted", ["member"]],
        ["submitted", "approved", ["admin"]],
        ["submitted", "rejected", %w[admin system]]
      ])
      expect(lifecycle.label("submitted")).to eq("Submitted")
    end

    it "is in force on a radio as well" do
      expect(described_class.from_attribute(status.merge("html_type" => "radio"))).to be_present
    end

    it "is not in force on a control that is not a single choice" do
      expect(described_class.from_attribute(status.merge("html_type" => "text"))).to be_nil
      expect(described_class.from_attribute(status.merge("html_type" => "checkbox"))).to be_nil
    end

    it "is not in force on a derived attribute" do
      expect(described_class.from_attribute(status.merge("type" => "Computed"))).to be_nil
    end

    it "is not in force when the options come from a constant or another entity" do
      expect(described_class.from_attribute(status.deep_merge("config" => { "source" => "constant", "constant_id" => 1 }))).to be_nil
      expect(described_class.from_attribute(status.deep_merge("config" => { "options_source" => "entity", "options_entity_name" => "Course" }))).to be_nil
    end

    it "needs exactly one default option" do
      none = options.map { |option| option.except("default") }
      two = options.each_with_index.map { |option, index| index < 2 ? option.merge("default" => true) : option }

      expect(described_class.from_attribute(status.deep_merge("config" => { "options" => none }))).to be_nil
      expect(described_class.from_attribute(status.deep_merge("config" => { "options" => two }))).to be_nil
    end

    it "ignores transitions naming missing states, self changes, unknown audiences and repeats" do
      rows = transitions + [
        { "from" => "draft", "to" => "archived", "by" => %w[admin] },
        { "from" => "draft", "to" => "draft", "by" => %w[admin] },
        { "from" => "approved", "to" => "rejected", "by" => %w[guest] },
        { "from" => "draft", "to" => "submitted", "by" => %w[admin] }
      ]
      lifecycle = described_class.from_attribute(status.merge("lifecycle" => { "transitions" => rows }))

      expect(lifecycle.transitions.size).to eq(3)
    end

    it "is not in force without a usable transition or without a lifecycle hash" do
      expect(described_class.from_attribute(status.merge("lifecycle" => { "transitions" => [] }))).to be_nil
      expect(described_class.from_attribute(status.merge("lifecycle" => "draft"))).to be_nil
      expect(described_class.from_attribute(status.except("lifecycle"))).to be_nil
    end
  end

  describe ".next_states" do
    it "lists every state one transition away, whoever causes it" do
      expect(described_class.next_states(entity, "status", "submitted")).to eq(%w[approved rejected])
    end

    it "narrows to the audience given" do
      expect(described_class.next_states(entity, "status", "submitted", audience: "system")).to eq(%w[rejected])
      expect(described_class.next_states(entity, "status", "submitted", audience: "member")).to eq([])
      expect(described_class.next_states(entity, "status", "submitted", audience: "owner")).to eq(%w[approved rejected])
    end

    it "starts a blank or unknown state at the initial state" do
      expect(described_class.next_states(entity, "status", nil)).to eq(%w[draft submitted])
      expect(described_class.next_states(entity, "status", "archived", audience: "admin")).to eq(%w[draft])
    end

    it "is empty for an attribute without a lifecycle" do
      expect(described_class.next_states(entity, "title", "draft")).to eq([])
    end
  end

  describe ".audience!" do
    it "treats the platform owner as admin and refuses anything else" do
      expect(described_class.audience!("owner")).to eq("admin")
      expect(described_class.audience!(:system)).to eq("system")
      expect { described_class.audience!("guest") }.to raise_error(ArgumentError)
      expect { described_class.audience!(nil) }.to raise_error(ArgumentError)
    end
  end

  describe ".violations on a new record" do
    it "allows a blank value or the initial state" do
      expect(violations(new_entry("title" => "A"), "public")).to eq([])
      expect(violations(new_entry("status" => "draft"), "public")).to eq([])
    end

    it "allows one step from the initial state the audience may take" do
      expect(violations(new_entry("status" => "submitted"), "member")).to eq([])
    end

    it "refuses a step the audience may not take, naming the option labels" do
      result = violations(new_entry("status" => "submitted"), "admin")

      expect(result.map(&:to_h)).to eq([{ slug: "status", from: "draft", to: "submitted",
                                          message: "can't move from Draft to Submitted" }])
    end

    it "refuses a state more than one step from the initial state" do
      expect(violations(new_entry("status" => "approved"), "admin").map(&:to)).to eq(["approved"])
    end
  end

  describe ".violations on a saved record" do
    it "allows a change the transition lists for the audience" do
      entry = saved_entry("status" => "submitted")
      entry.status = "approved"

      expect(violations(entry, "admin")).to eq([])
      expect(violations(entry, "owner")).to eq([])
    end

    it "refuses the same change for an audience the transition does not list" do
      entry = saved_entry("status" => "submitted")
      entry.status = "approved"

      expect(violations(entry, "member").map(&:message)).to eq(["can't move from Submitted to Approved"])
      expect(violations(entry, "system").size).to eq(1)
    end

    it "accepts an unchanged value, including one no transition reaches" do
      entry = saved_entry("status" => "approved")
      entry.title = "Renamed"

      expect(violations(entry, "public")).to eq([])
    end

    it "refuses clearing the value" do
      entry = saved_entry("status" => "submitted")
      entry.status = ""

      expect(violations(entry, "admin").map(&:message)).to eq(["can't be cleared once it is Submitted"])
    end

    it "treats a blank stored value as the initial state" do
      entry = saved_entry("title" => "Legacy")
      entry.status = "draft"
      expect(violations(entry, "public")).to eq([])

      entry.status = "submitted"
      expect(violations(entry, "member")).to eq([])
      expect(violations(entry, "admin").map(&:from)).to eq(["draft"])
    end

    it "treats a stored value that is not a state as the initial state" do
      entry = saved_entry("status" => "archived")
      entry.status = "draft"
      expect(violations(entry, "admin")).to eq([])

      entry.status = "approved"
      expect(violations(entry, "admin").map(&:message)).to eq(["can't move from archived to Approved"])
    end
  end

  it "has nothing to check on an entity without lifecycles" do
    plain = create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" }
    ].to_json)
    entry = EntityEntry.build_for(plain).new(entity: plain, customer_id: customer.id)

    expect(violations(entry, "public")).to eq([])
  end
end
