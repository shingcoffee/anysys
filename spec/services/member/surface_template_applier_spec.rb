# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::SurfaceTemplateApplier do
  subject(:detail) { described_class.call(entity: entity) }

  let_it_be(:customer) { create(:customer) }

  # Definition body (groups/attributes) is virtual/head-content backed; set via *_json= + save,
  # then reload so the applier reads a committed head. save(validate: false) mirrors the group
  # styling bypass used by the callers under test.
  def build_entity(groups:, properties:)
    e = create(:entity, customer: customer)
    e.attribute_groups_json = groups
    e.property_schema_json   = properties
    e.save(validate: false)
    Entity.find(e.id)
  end

  let(:entity) do
    build_entity(
      groups: [
        { "id" => "g_account", "name" => "Account" },
        { "id" => "g_profile", "name" => "Profile" }
      ],
      properties: [
        { "name" => "Email", "name_slug" => "email", "type" => "string", "html_type" => "email",
          "group_id" => "g_account",
          "visibility" => { "admin" => true, "member" => true, "public" => false } },
        { "name" => "Password", "name_slug" => "password", "type" => "string", "html_type" => "password",
          "group_id" => "g_account",
          "visibility" => { "admin" => true, "member" => false, "public" => false } },
        { "name" => "Bio", "name_slug" => "bio", "type" => "string", "html_type" => "textarea",
          "group_id" => "g_profile" },
        { "name" => "Score", "name_slug" => "score", "type" => "number", "html_type" => "number",
          "group_id" => nil },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
          "group_id" => nil }
      ]
    )
  end


  it "returns a Member::Surface::Detail" do
    expect(detail).to be_a(Member::Surface::Detail)
  end

  it "emits one section per non-empty attribute group" do
    titles = detail.sections.map { |s| s[:title] }
    expect(titles).to eq(["Account", "Profile", "Additional"])
  end

  it "filters out attributes with visibility.member == false" do
    slugs = detail.sections.flat_map { |s| s[:rows].map { |r| r[:key] } }
    expect(slugs).to include(:email)
    expect(slugs).not_to include(:password)
  end

  it "excludes Calculated attributes (matches EntitySurfaceBuilder behavior)" do
    slugs = detail.sections.flat_map { |s| s[:rows].map { |r| r[:key] } }
    expect(slugs).not_to include(:total)
  end

  it "maps width=full to span=2 and other widths to span=1" do
    bio_row = detail.sections.flat_map { |s| s[:rows] }.find { |r| r[:key] == :bio }
    score_row = detail.sections.flat_map { |s| s[:rows] }.find { |r| r[:key] == :score }
    expect(bio_row[:span]).to eq(2)    # textarea -> full -> 2
    expect(score_row[:span]).to eq(1)  # number -> half -> 1
  end

  it "exposes a value lambda that reads display_text by name_slug" do
    entry = double("EntityEntry", id: 7, created_at: Time.current)
    allow(entry).to receive(:display_text).with("email").and_return("x@example.com")
    email_row = detail.sections.flat_map { |s| s[:rows] }.find { |r| r[:key] == :email }
    expect(email_row[:value].call(entry)).to eq("x@example.com")
  end

  it "title lambda formats entry.id with a # prefix" do
    entry = double("EntityEntry", id: 99, created_at: Time.current,
                                  data_json: { "email" => "t@example.com" })
    expect(detail.title.call(entry)).to eq("#99")
  end

  it "value lambda returns nil when entry does not respond to display_text" do
    bare_entry = double("BareEntry", id: 7, created_at: Time.current)
    email_row = detail.sections.flat_map { |s| s[:rows] }.find { |r| r[:key] == :email }
    expect(email_row[:value].call(bare_entry)).to be_nil
  end

  it "subtitle lambda formats entry.created_at" do
    frozen = Time.zone.local(2026, 3, 15, 9, 0, 0)
    entry = double("EntityEntry", id: 42, created_at: frozen,
                                  data_json: { "email" => "y@example.com" })
    subtitle = detail.subtitle
    expect(subtitle.call(entry)).to be_a(String)
    expect(subtitle.call(entry)).not_to be_blank
  end

  it "returns nil when no template is registered for the given key" do
    expect(described_class.call(entity: entity, template_key: "nonexistent_key")).to be_nil
  end

  context "when an entity group is empty after visibility filtering" do
    let(:entity) do
      build_entity(
        groups: [
          { "id" => "g_secrets", "name" => "Secrets" },
          { "id" => "g_visible", "name" => "Visible" }
        ],
        properties: [
          { "name" => "SSN", "name_slug" => "ssn", "type" => "string", "html_type" => "text",
            "group_id" => "g_secrets",
            "visibility" => { "member" => false } },
          { "name" => "Nick", "name_slug" => "nick", "type" => "string", "html_type" => "text",
            "group_id" => "g_visible" }
        ]
      )
    end

    it "skips the empty group" do
      titles = detail.sections.map { |s| s[:title] }
      expect(titles).not_to include("Secrets")
      expect(titles).to include("Visible")
    end
  end

  context "with attributes that have a nil or blank name_slug" do
    let(:entity) do
      build_entity(
        groups: [{ "id" => "g_one", "name" => "Group" }],
        properties: [
          { "name" => "Has Slug", "name_slug" => "has_slug", "type" => "string",
            "html_type" => "text", "group_id" => "g_one" },
          { "name" => "Nil Slug", "name_slug" => nil, "type" => "string",
            "html_type" => "text", "group_id" => "g_one" },
          { "name" => "Blank Slug", "name_slug" => "", "type" => "string",
            "html_type" => "text", "group_id" => "g_one" }
        ]
      )
    end

    it "skips them rather than emitting empty-keyed rows that would fail validate_detail!" do
      slugs = detail.sections.flat_map { |s| s[:rows].map { |r| r[:key] } }
      expect(slugs).to eq([:has_slug])
    end

    it "does not raise when the constructed Detail is validated" do
      expect { Member::Surface.new(
        key: :probe, label: "Probe", icon: :info,
        enabled_for: ->(_) { true },
        index: Member::Surface::Index.new(title: "x", scope: ->(_) { EntityEntry.none },
                                               columns: [{ key: :id, label: "ID", value: ->(_) { 1 } }]),
        detail: detail
      ).validate! }.not_to raise_error
    end
  end

  context "with a Computed attribute" do
    let(:entity) do
      build_entity(
        groups: [{ "id" => "g_one", "name" => "Grades" }],
        properties: [
          { "name" => "Name", "name_slug" => "name", "type" => "string", "html_type" => "text",
            "group_id" => "g_one" },
          { "name" => "Average Score", "name_slug" => "average_score", "type" => "Computed",
            "html_type" => "number", "group_id" => "g_one" },
          { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
            "group_id" => "g_one" }
        ]
      )
    end

    it "produces a detail row whose value lambda reads display_text" do
      row = detail.sections.flat_map { |s| s[:rows] }.find { |r| r[:key] == :average_score }
      expect(row).to be_present

      entry = create(:entity_entry, entity: entity, customer: customer, data: { "name" => "John" }.to_json)
      allow(entry).to receive(:display_text).with("average_score").and_return("87.5")

      expect(row[:value].call(entry)).to eq("87.5")
      expect(entry).to have_received(:display_text)
    end

    it "still excludes Calculated attributes" do
      slugs = detail.sections.flat_map { |s| s[:rows].map { |r| r[:key] } }
      expect(slugs).to include(:average_score)
      expect(slugs).not_to include(:total)
    end
  end
end
