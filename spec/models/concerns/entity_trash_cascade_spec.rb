# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entity, "trash cascade to forms" do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  it "takes every launched form bound to the entity offline and counts them" do
    entity = create(:entity, customer: customer, name: "Timesheet")
    live = create(:page, customer: customer, entity: entity, launched: true)
    draft = create(:page, customer: customer, entity: entity, launched: false)
    unrelated = create(:page, customer: customer, launched: true)

    expect(entity.soft_delete).to be_truthy
    expect(entity.forms_taken_offline).to eq(1)
    expect([live, draft, unrelated].map { |page| page.reload.launched }).to eq([false, false, true])
  end

  it "covers every tenant's forms for a shared entity" do
    shared = Current.set(shared_resources_mode: true) { create(:entity, :shared, name: "Campus") }
    mine = create(:page, customer: customer, entity: shared, launched: true)
    theirs = create(:page, customer: other_customer, entity: shared, launched: true)

    trashed = Current.set(shared_resources_mode: true) { described_class.find(shared.id).tap(&:soft_delete) }

    expect(trashed.forms_taken_offline).to eq(2)
    expect([mine, theirs].map { |page| page.reload.launched }).to eq([false, false])
  end

  it "takes a shared form offline while its shared entity is still active" do
    shared, form = Current.set(shared_resources_mode: true) do
      entity = create(:entity, :shared)
      [entity, create(:page, :shared, entity: entity, launched: true)]
    end

    Current.set(shared_resources_mode: true) { expect(described_class.find(shared.id).soft_delete).to be_truthy }
    expect(form.reload.launched).to be(false)
  end

  it "rolls the trash back when a form can't be taken offline" do
    entity = create(:entity, customer: customer)
    form = create(:page, customer: customer, entity: entity, launched: true)
    locked = Page.new.tap { |record| record.errors.add(:base, "Form is locked") }
    allow_any_instance_of(Page).to receive(:take_offline!).and_raise(ActiveRecord::RecordInvalid.new(locked))

    expect(entity.soft_delete).to be(false)
    expect(entity.errors[:base]).to include("Form is locked")
    expect(entity.forms_taken_offline).to eq(0)
    expect(described_class.find(entity.id)).to be_active
    expect(form.reload.launched).to be(true)
  end
end
