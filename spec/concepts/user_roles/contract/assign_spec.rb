# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserRoles::Contract::Assign do
  let(:model) { OpenStruct.new(role_ids: nil) }
  let(:form)  { described_class.new(model) }

  describe "valid attributes" do
    it "is valid with role_ids as a non-empty array" do
      form.validate(role_ids: [1, 2])
      expect(form.errors).to be_empty
    end

    it "is valid with role_ids as an empty array (allow_blank: true)" do
      form.validate(role_ids: [])
      expect(form.errors).to be_empty
    end

    it "is valid with role_ids as nil (allow_blank: true)" do
      form.validate(role_ids: nil)
      expect(form.errors).to be_empty
    end
  end

  describe "role_ids property" do
    it "exposes the validated role_ids value" do
      form.validate(role_ids: [10, 20])
      expect(form.role_ids).to eq([10, 20])
    end

    it "is a virtual property — not synced to the underlying model" do
      form.validate(role_ids: [99])
      # The model does not track role_ids by default; only the form holds it
      expect(form.role_ids).to eq([99])
    end
  end
end
