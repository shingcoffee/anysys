# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Surface do
  def valid_index
    Member::Surface::Index.new(
      title:    "Things",
      subtitle: "All your things",
      scope:    ->(_user) { [] },
      columns:  [
        { key: :name,   label: "Name",   value: ->(r) { r.name } },
        { key: :amount, label: "Amount", value: ->(r) { r.amount }, format: :money, align: :right }
      ],
      empty_state: { headline: "Nothing yet", body: "It will show up", icon: :sparkles },
      per_page: 20
    )
  end

  def valid_detail
    Member::Surface::Detail.new(
      title:    ->(r) { r.name },
      subtitle: ->(_r) { "subtitle" },
      meta:     ->(_r) { { label: "ok", tone: :success } },
      sections: [
        { key: :primary, rows: [{ key: :name, label: "Name", value: ->(r) { r.name } }] }
      ]
    )
  end

  def valid_surface
    described_class.new(
      key:         :things,
      label:       "Things",
      icon:        :sparkles,
      enabled_for: ->(_user) { true },
      index:       valid_index,
      detail:      valid_detail
    )
  end

  # Minimal Index whose only variable is the columns list under test.
  def index_with(columns:)
    Member::Surface::Index.new(
      title: "T", scope: ->(_u) { [] }, columns: columns,
      empty_state: { headline: "x", body: "y", icon: :z }, per_page: 10
    )
  end

  # Minimal Detail whose only variable is the sections list under test.
  def detail_with(sections:)
    Member::Surface::Detail.new(title: ->(_r) { "T" }, sections: sections)
  end

  describe "#validate!" do
    it "passes for a fully populated surface" do
      expect { valid_surface.validate! }.not_to raise_error
    end

    it "rejects a key with uppercase letters" do
      surface = valid_surface
      surface.key = :Things
      expect { surface.validate! }.to raise_error(ArgumentError, /key/)
    end

    it "rejects a key starting with a digit" do
      surface = valid_surface
      surface.key = :"1thing"
      expect { surface.validate! }.to raise_error(ArgumentError, /key/)
    end

    it "rejects a blank label" do
      surface = valid_surface
      surface.label = ""
      expect { surface.validate! }.to raise_error(ArgumentError, /label/)
    end

    it "rejects when index is not an Index" do
      surface = valid_surface
      surface.index = nil
      expect { surface.validate! }.to raise_error(ArgumentError, /index/)
    end

    it "rejects when detail is not a Detail" do
      surface = valid_surface
      surface.detail = nil
      expect { surface.validate! }.to raise_error(ArgumentError, /detail/)
    end

    it "rejects an Index without columns" do
      bad = valid_surface
      bad.index = index_with(columns: [])
      expect { bad.validate! }.to raise_error(ArgumentError, /columns/)
    end

    it "rejects a column missing :key" do
      bad = valid_surface
      bad.index = index_with(columns: [{ label: "X", value: ->(r) { r } }])
      expect { bad.validate! }.to raise_error(ArgumentError, /key/)
    end

    it "rejects a column missing :label" do
      bad = valid_surface
      bad.index = index_with(columns: [{ key: :x, value: ->(r) { r } }])
      expect { bad.validate! }.to raise_error(ArgumentError, /column.*label/)
    end

    it "rejects a column missing :value" do
      bad = valid_surface
      bad.index = index_with(columns: [{ key: :x, label: "X" }])
      expect { bad.validate! }.to raise_error(ArgumentError, /column.*value/)
    end

    it "rejects a section missing :key" do
      bad = valid_surface
      bad.detail = detail_with(sections: [{ rows: [{ key: :x, label: "X", value: ->(_r) { "v" } }] }])
      expect { bad.validate! }.to raise_error(ArgumentError, /section.*key/)
    end

    it "rejects a section row missing :key" do
      bad = valid_surface
      bad.detail = detail_with(sections: [{ key: :primary, rows: [{ label: "X", value: ->(_r) { "v" } }] }])
      expect { bad.validate! }.to raise_error(ArgumentError, /row.*key/)
    end
  end

  describe "#enabled_for?" do
    it "delegates to the lambda" do
      surface = valid_surface
      surface.enabled_for = ->(_u) { false }
      expect(surface.enabled_for?(double)).to be(false)
    end
  end

  describe "#default_enabled?" do
    it "is true unless default_enabled is false" do
      expect(valid_surface.default_enabled?).to be(true)

      surface = valid_surface
      surface.default_enabled = false
      expect(surface.default_enabled?).to be(false)
    end
  end

  describe "#default_position_or_default" do
    it "returns the configured default_position" do
      surface = valid_surface
      surface.default_position = 50
      expect(surface.default_position_or_default).to eq(50)
    end

    it "falls back to DEFAULT_POSITION when nil" do
      surface = valid_surface
      surface.default_position = nil
      expect(surface.default_position_or_default).to eq(Member::Surface::DEFAULT_POSITION)
    end
  end
end
