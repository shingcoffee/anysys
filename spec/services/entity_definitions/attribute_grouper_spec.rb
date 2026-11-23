# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::AttributeGrouper do
  def attr(name, slug: nil, group_id: nil, html_type: "text")
    { "name" => name, "name_slug" => slug || name.parameterize(separator: "_"), "html_type" => html_type, "group_id" => group_id }.compact
  end

  it "honors LLM groups, group_id values, and array order" do
    result = described_class.call(
      attributes: [
        attr("Email", slug: "email", group_id: "g_contact", html_type: "email"),
        attr("First name", slug: "first_name", group_id: "g_identity")
      ],
      incoming_groups: [
        { "id" => "g_contact", "name" => "Contact", "icon" => "mail", "color" => "sky" },
        { "id" => "g_identity", "name" => "Identity", "icon" => "user", "color" => "indigo" }
      ]
    )

    expect(result.groups.map { |row| row["id"] }).to eq(%w[g_contact g_identity])
    expect(result.attributes.map { |row| row["group_id"] }).to eq(%w[g_contact g_identity])
  end

  it "does not invent groups when the model omitted them" do
    result = described_class.call(
      attributes: [
        attr("First name", slug: "first_name"),
        attr("Last name", slug: "last_name"),
        attr("Email", slug: "email", html_type: "email"),
        attr("Phone", slug: "phone", html_type: "tel")
      ]
    )

    expect(result.groups).to eq([])
    expect(result.attributes).to all(satisfy { |row| row["group_id"].blank? })
  end

  it "keeps omitted catalog groups and appends newly supplied groups in incoming order" do
    result = described_class.call(
      attributes: [attr("Street", slug: "street", group_id: "g_address")],
      existing_groups: [{ "id" => "g_contact", "name" => "Contact", "icon" => "mail", "color" => "sky" }],
      incoming_groups: [{ "id" => "g_address", "name" => "Address", "icon" => "map-pin", "color" => "teal" }]
    )

    expect(result.groups.map { |row| row["id"] }).to eq(%w[g_contact g_address])
  end

  it "uses the incoming array as page order when the model restates groups" do
    result = described_class.call(
      attributes: [
        attr("Hire date", slug: "hire_date", group_id: "g_dates", html_type: "date"),
        attr("Full name", slug: "full_name", group_id: "g_identity")
      ],
      existing_groups: [
        { "id" => "g_dates", "name" => "Dates", "icon" => "calendar", "color" => "amber" },
        { "id" => "g_identity", "name" => "Identity", "icon" => "user", "color" => "indigo" }
      ],
      incoming_groups: [
        { "id" => "g_identity", "name" => "Identity", "icon" => "user", "color" => "indigo" },
        { "id" => "g_dates", "name" => "Dates", "icon" => "calendar", "color" => "amber" }
      ]
    )

    expect(result.groups.map { |row| row["id"] }).to eq(%w[g_identity g_dates])
  end
end
