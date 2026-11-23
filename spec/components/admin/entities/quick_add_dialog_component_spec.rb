# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::QuickAddDialogComponent, type: :component do
  it "renders a labelled modal dialog hosting the quick-add frame" do
    render_inline(described_class.new)

    dialog = page.find("dialog#entity-quick-add-dialog-0", visible: :all)
    expect(dialog["data-controller"]).to eq("entity-quick-add-dialog")
    expect(dialog["aria-labelledby"]).to eq("entity-quick-add-title-0")
    expect(dialog["data-action"].split).to contain_exactly(
      "click->entity-quick-add-dialog#backdrop",
      "close->entity-quick-add-dialog#reset",
      "turbo:frame-missing->entity-quick-add-dialog#missing"
    )
    expect(page).to have_css("h2#entity-quick-add-title-0[data-entity-quick-add-dialog-target='title']", visible: :all)
    expect(page).to have_css("turbo-frame#entity-quick-add-frame-0[data-entity-quick-add-dialog-target='frame']", visible: :all)
    expect(page.find("button[data-action='entity-quick-add-dialog#close']", visible: :all)["aria-label"])
      .to eq(I18n.t("common.actions.close"))
  end

  it "renders nothing past the deepest level" do
    expect(render_inline(described_class.new(depth: described_class::MAX_DEPTH + 1)).to_html).to be_blank
  end

  it "names a nested level's dialog, title and frame by its depth" do
    render_inline(described_class.new(depth: 2))

    dialog = page.find("dialog#entity-quick-add-dialog-2", visible: :all)
    expect(dialog["aria-labelledby"]).to eq("entity-quick-add-title-2")
    expect(page).to have_css("h2#entity-quick-add-title-2", visible: :all)
    expect(page).to have_css("turbo-frame#entity-quick-add-frame-2", visible: :all)
  end

  it "ships translated loading and failure templates" do
    I18n.with_locale(:"zh-CN") { render_inline(described_class.new) }

    expect(rendered_content).to match(
      %r{<template data-entity-quick-add-dialog-target="loading">.*#{I18n.t("admin_misc.entities.quick_add.loading", locale: :"zh-CN")}.*?</template>}m
    )
    expect(rendered_content).to match(
      %r{<template data-entity-quick-add-dialog-target="failure">.*#{I18n.t("admin_misc.entities.quick_add.unavailable", locale: :"zh-CN")}.*?</template>}m
    )
  end

  describe ".depth_of" do
    it "reads the level from a quick-add frame id" do
      expect(described_class.depth_of("entity-quick-add-frame-0")).to eq(0)
      expect(described_class.depth_of("entity-quick-add-frame-#{described_class::MAX_DEPTH}")).to eq(described_class::MAX_DEPTH)
    end

    it "is nil for other frames, unsuffixed or out-of-range ids" do
      [nil, "", "something-else", "entity-quick-add-frame", "entity-quick-add-frame-x",
       "entity-quick-add-frame-#{described_class::MAX_DEPTH + 1}", "entity-quick-add-frame-123",
       "entity-quick-add-frame-1\nentity-quick-add-frame-2"].each do |frame_id|
        expect(described_class.depth_of(frame_id)).to be_nil
      end
    end
  end

  describe ".opener" do
    let(:customer) { create(:customer) }
    let(:entity) { create(:entity, customer: customer, name: "Teacher", display_label: "Tutor") }

    it "points the dropdown at the level's dialog and the entity's Create Entry form" do
      expect(described_class.opener(entity: entity, customer_id: customer.id, label_field: "name", depth: 1)).to eq(
        url: "/#{customer.id}/admin/entities/#{entity.id}/entries/new?label_field=name",
        label: I18n.t("admin_misc.entities.quick_add.option"),
        title: I18n.t("admin_misc.entities.quick_add.title", name: "Tutor"),
        dialog: "#entity-quick-add-dialog-1"
      )
    end

    it "falls back to the entity name and drops a blank label field" do
      entity.update_columns(display_label: "")

      opener = described_class.opener(entity: entity, customer_id: customer.id, label_field: nil, depth: 0)
      expect(opener[:url]).to eq("/#{customer.id}/admin/entities/#{entity.id}/entries/new")
      expect(opener[:title]).to eq(I18n.t("admin_misc.entities.quick_add.title", name: "Teacher"))
    end

    it "stops nesting past the maximum depth" do
      expect(described_class.opener(entity: entity, customer_id: customer.id, label_field: "name",
                                    depth: described_class::MAX_DEPTH + 1)).to be_nil
    end
  end
end
