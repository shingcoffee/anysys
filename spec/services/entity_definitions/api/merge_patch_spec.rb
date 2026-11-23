# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::Api::MergePatch do
  def apply(target, patch)
    described_class.apply(target, patch)
  end

  it "merges objects, replaces arrays, and deletes null keys" do
    target = {
      "name" => "Email",
      "access" => { "visible_to" => { "admin" => true, "member" => true, "public" => true } },
      "rules" => [{ "type" => "presence" }],
      "description" => "Work"
    }

    result = apply(target, {
      "access" => { "visible_to" => { "public" => false } },
      "rules" => [{ "type" => "format_email" }],
      "description" => nil,
      "display_label" => "E-mail"
    })

    expect(result["access"]["visible_to"]).to eq("admin" => true, "member" => true, "public" => false)
    expect(result["rules"]).to eq([{ "type" => "format_email" }])
    expect(result).not_to have_key("description")
    expect(result["display_label"]).to eq("E-mail")
    expect(result["name"]).to eq("Email")
  end

  it "replaces the target when the patch is not an object" do
    expect(apply({ "a" => 1 }, [1, 2])).to eq([1, 2])
    expect(apply({ "a" => 1 }, "x")).to eq("x")
  end

  it "stringifies keys" do
    expect(apply({ a: { b: 1 } }, { a: { c: 2 } })).to eq("a" => { "b" => 1, "c" => 2 })
  end
end
