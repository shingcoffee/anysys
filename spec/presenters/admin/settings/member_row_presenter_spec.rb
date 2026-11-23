# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Settings::MemberRowPresenter do
  def presenter_for(sections)
    descriptor = Member::Surface.new(
      key: :widgets,
      label: "Widgets",
      icon: :cube,
      enabled_for: ->(_) { true },
      index: Member::Surface::Index.new(
        title: "Widgets",
        scope: ->(_) { [] },
        columns: [{ key: :id, label: "Id", value: ->(r) { r.id } }]
      ),
      detail: Member::Surface::Detail.new(
        title: ->(_) { "T" },
        sections: sections
      )
    )
    effective = Member::EffectiveSurface.new(
      descriptor: descriptor,
      settings: Member::NullSurfaceSetting.new,
      source_key: :modules
    )
    described_class.new(effective: effective)
  end

  describe "#section_choices" do
    it "uses the i18n label for an untitled primary section" do
      label = presenter_for([{ key: :primary, rows: [] }]).section_choices.first[:label]
      expect(label).to eq("Primary")
    end

    it "localizes an untitled primary section in zh-CN" do
      I18n.with_locale(:"zh-CN") do
        label = presenter_for([{ key: :primary, rows: [] }]).section_choices.first[:label]
        expect(label).to eq("主要")
      end
    end

    it "keeps an explicit section title" do
      label = presenter_for([{ key: :refunds, title: "Refunds", rows: [] }]).section_choices.first[:label]
      expect(label).to eq("Refunds")
    end

    it "uses a readable fallback for an unknown untitled section without exposing its key" do
      label = presenter_for([{ key: :misc_group, rows: [] }]).section_choices.first[:label]
      expect(label).to eq("Details")
    end
  end

  it "names generated relationship pages from their participant display labels" do
    descriptor = Member::Surface.new(key: :entity_42, label: "assoc_students_classes",
      groups: [{ attributes: [
        { "type" => "EntityReference", "name" => "Students" },
        { "type" => "EntityReference", "name" => "Classes" }
      ] }])
    effective = Member::EffectiveSurface.new(descriptor: descriptor, settings: Member::NullSurfaceSetting.new, source_key: :entities)
    expect(described_class.new(effective: effective).label).to eq("Students and Classes")
    expect(described_class.new(effective: effective).subtitle).to eq("View your Students and Classes records.")
    expect(described_class.new(effective: effective).empty_headline).to eq("No students and classes yet")
    I18n.with_locale(:"zh-CN") do
      expect(described_class.new(effective: effective).label).to eq("Students与Classes")
    end
  end
end
