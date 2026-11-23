# frozen_string_literal: true

require "rails_helper"

RSpec.describe RolePermission, type: :model do
  describe "validations" do
    it "requires subject_type" do
      rp = build(:role_permission, subject_type: nil)
      expect(rp).not_to be_valid
    end

    it "requires action" do
      rp = build(:role_permission, action: nil)
      expect(rp).not_to be_valid
    end

    it "rejects subject_type outside the allowed list" do
      rp = build(:role_permission, subject_type: "InvalidType")
      expect(rp).not_to be_valid
      expect(rp.errors[:subject_type]).to be_present
    end

    it "rejects action outside the allowed list" do
      rp = build(:role_permission, action: "exfiltrate")
      expect(rp).not_to be_valid
      expect(rp.errors[:action]).to be_present
    end

    described_class::ACTIONS.each do |action|
      it "accepts the #{action.inspect} action" do
        expect(build(:role_permission, action: action)).to be_valid
      end
    end

    describe "key-based subjects (Route, Module, FeaturePage, Platform, EntityClass, PageClass)" do
      it "requires subject_key" do
        rp = build(:role_permission, subject_type: "Route", subject_key: nil, subject_id: nil)
        expect(rp).not_to be_valid
        expect(rp.errors[:subject_key]).to be_present
      end

      it "rejects subject_id" do
        rp = build(:role_permission, subject_type: "Module",
                                    subject_key: "payments", subject_id: 1)
        expect(rp).not_to be_valid
        expect(rp.errors[:subject_id]).to be_present
      end
    end

    describe "instance-based subjects (Entity, Page)" do
      it "requires subject_id for Entity" do
        rp = build(:role_permission, subject_type: "Entity", subject_id: nil, subject_key: nil)
        expect(rp).not_to be_valid
        expect(rp.errors[:subject_id]).to be_present
      end

      it "rejects subject_key for Entity" do
        rp = build(:role_permission, subject_type: "Entity",
                                    subject_id: 1, subject_key: "leak")
        expect(rp).not_to be_valid
        expect(rp.errors[:subject_key]).to be_present
      end

      it "permits well-formed Entity instance grant" do
        expect(build(:role_permission, :entity_instance)).to be_valid
      end
    end
  end
end
