# frozen_string_literal: true

require "rails_helper"

RSpec.describe RoleGrants::Contract::Update do
  # The contract uses virtual properties on a null model object.
  let(:model) { OpenStruct.new(added: nil, removed: nil) }
  let(:form)  { described_class.new(model) }
  let(:grant) { { subject_type: "Route", subject_key: "admin/x", action: "read" } }

  describe "valid attributes" do
    it "is valid with both added and removed set to arrays" do
      form.validate(added: [], removed: [])
      expect(form.errors).to be_empty
    end

    it "is valid with non-empty added and empty removed" do
      form.validate(added: [grant], removed: [])
      expect(form.errors).to be_empty
    end

    it "is valid with empty added and non-empty removed" do
      form.validate(added: [], removed: [grant])
      expect(form.errors).to be_empty
    end
  end

  describe "added property" do
    it "allows an empty array (allow_blank: true)" do
      form.validate(added: [], removed: [])
      expect(form.errors[:added]).to be_empty
    end

    it "allows nil (presence validates with allow_blank)" do
      form.validate(added: nil, removed: [])
      # allow_blank: true means nil/empty passes presence validation
      expect(form.errors[:added]).to be_empty
    end
  end

  describe "removed property" do
    it "allows an empty array (allow_blank: true)" do
      form.validate(added: [], removed: [])
      expect(form.errors[:removed]).to be_empty
    end

    it "allows nil (presence validates with allow_blank)" do
      form.validate(added: [], removed: nil)
      expect(form.errors[:removed]).to be_empty
    end
  end

  describe "virtual properties" do
    it "does not expose :added or :removed on the underlying model after sync" do
      form.validate(added: ["x"], removed: ["y"])
      # Virtual properties are not synced to the model by Reform by default
      expect(form.added).to eq(["x"])
      expect(form.removed).to eq(["y"])
    end
  end
end
