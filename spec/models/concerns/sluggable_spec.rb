# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sluggable do
  let(:sluggable_class) do
    stub_const("SluggableSample", Class.new(ApplicationRecord) do
      self.table_name = "entities"
      enum :status, { active: 0, inactive: 1 }, default: :active
      include Sluggable
      sluggable source: :name,
                slug_column: :extended_model,
                scope: :customer_id,
                uniqueness_conditions: -> { where.not(status: statuses[:inactive]) }
    end)
  end

  describe "slug generation" do
    let_it_be(:customer) { create(:customer) }

    def slug_for(name)
      record = sluggable_class.new(name: name, customer_id: customer.id)
      record.valid?
      record.extended_model
    end

    it "parameterizes the name into an underscored slug" do
      expect(slug_for("My Test Entity")).to eq("my_test_entity")
    end

    it "strips special characters" do
      expect(slug_for("Test & Entity #1!")).to eq("test_entity_1")
    end

    it "transliterates accented characters to ASCII" do
      expect(slug_for("Café Résumé")).to eq("cafe_resume")
    end

    it "collapses multiple spaces and underscores into a single underscore" do
      expect(slug_for("Test   Multiple   Spaces")).to eq("test_multiple_spaces")
    end

    it "trims leading and trailing whitespace" do
      expect(slug_for("  Padded Name  ")).to eq("padded_name")
    end

    it "returns nil for an empty name" do
      expect(slug_for("")).to be_nil
    end

    it "returns nil for a nil name" do
      record = sluggable_class.new(customer_id: customer.id)
      record.valid?

      expect(record.extended_model).to be_nil
    end
  end

  describe ".slugify class method" do
    it "generates slug from string" do
      expect(sluggable_class.slugify("Test Entity")).to eq("test_entity")
    end

    it "accepts custom separator" do
      expect(sluggable_class.slugify("Test Entity", separator: "-")).to eq("test-entity")
    end

    it "returns nil for blank input" do
      expect(sluggable_class.slugify("")).to be_nil
      expect(sluggable_class.slugify(nil)).to be_nil
    end

    it "handles numbers" do
      expect(sluggable_class.slugify("Entity 123")).to eq("entity_123")
    end
  end

  describe "uniqueness validation" do
    let(:customer) { create(:customer) }

    it "validates uniqueness within scope" do
      sluggable_class.create!(name: "Test Entity", customer_id: customer.id)
      duplicate = sluggable_class.new(name: "Test Entity", customer_id: customer.id)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:extended_model]).to include("has already been taken")
    end

    it "allows same slug for different customers" do
      other_customer = create(:customer)
      sluggable_class.create!(name: "Test Entity", customer_id: customer.id)
      other_record = sluggable_class.new(name: "Test Entity", customer_id: other_customer.id)

      expect(other_record).to be_valid
    end

    it "allows the same slug when the only conflict is an inactive record" do
      sluggable_class.create!(name: "student", customer_id: customer.id, status: :inactive)
      replacement = sluggable_class.new(name: "Student", customer_id: customer.id)

      expect(replacement).to be_valid
    end
  end
end
