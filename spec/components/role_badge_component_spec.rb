# frozen_string_literal: true

require "rails_helper"

RSpec.describe RoleBadgeComponent, type: :component do
  describe "#initialize" do
    it "accepts a role as symbol" do
      expect(described_class.new(role: :owner).role).to eq(:owner)
    end

    it "converts string role to symbol" do
      expect(described_class.new(role: "admin").role).to eq(:admin)
    end
  end

  describe "#role_classes" do
    {
      owner:  { bg: "bg-emerald-100", text: "text-emerald-800" },
      admin:  { bg: "bg-indigo-100",  text: "text-indigo-800"  },
      member: { bg: "bg-slate-100",   text: "text-slate-800"   }
    }.each do |role, expected|
      it "returns correct classes for #{role}" do
        classes = described_class.new(role: role).role_classes
        aggregate_failures do
          expect(classes).to include(expected[:bg])
          expect(classes).to include(expected[:text])
        end
      end
    end

    it "includes base classes for owner" do
      classes = described_class.new(role: :owner).role_classes
      aggregate_failures do
        expect(classes).to include("rounded-full")
        expect(classes).to include("text-xs")
        expect(classes).to include("font-medium")
      end
    end

    it "falls back to member style for unknown role" do
      expect(described_class.new(role: :unknown).role_classes).to include("bg-slate-100")
    end
  end

  describe "rendering" do
    {
      owner:  [ "bg-emerald-100", "Owner" ],
      admin:  [ "bg-indigo-100", "Admin" ],
      member: [ "bg-slate-100", "Member" ]
    }.each do |role, (css_class, label)|
      it "renders #{role} text with #{css_class} styling" do
        render_inline(described_class.new(role: role))
        aggregate_failures do
          expect(page).to have_text(label)
          expect(page).to have_css("span.#{css_class}")
        end
      end
    end
  end
end
