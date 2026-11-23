# frozen_string_literal: true

require "rails_helper"

RSpec.describe ComponentClasses do
  describe "button classes" do
    it "defines BTN_PRIMARY using the design-system btn-primary token" do
      classes = ComponentClasses::BTN_PRIMARY
      expect(classes).to include("btn")
      expect(classes).to include("btn-primary")
    end

    it "defines BTN_SECONDARY using the design-system btn-secondary token" do
      classes = ComponentClasses::BTN_SECONDARY
      expect(classes).to include("btn")
      expect(classes).to include("btn-secondary")
    end

    it "defines BTN_DANGER class" do
      expect(ComponentClasses::BTN_DANGER).to include("btn-danger")
    end

    it "defines BTN_SM class" do
      expect(ComponentClasses::BTN_SM).to include("px-2 py-1")
    end
  end

  describe "card classes" do
    it "defines CARD with required styles" do
      classes = ComponentClasses::CARD
      expect(classes).to include("bg-white")
      expect(classes).to include("border")
      expect(classes).to include("rounded-lg")
    end

    it "defines CARD_HOVER with hover effects" do
      classes = ComponentClasses::CARD_HOVER
      expect(classes).to include("hover:border-indigo-300")
      expect(classes).to include("hover:shadow-md")
    end
  end

  describe "input classes" do
    it "defines INPUT with required styles" do
      classes = ComponentClasses::INPUT
      expect(classes).to include("border")
      expect(classes).to include("rounded-lg")
      expect(classes).to include("focus:ring-2")
    end
  end

  describe "floating panel classes" do
    it "defines FLOATING_PANEL with required styles" do
      classes = ComponentClasses::FLOATING_PANEL
      expect(classes).to include("absolute")
      expect(classes).to include("bg-white")
      expect(classes).to include("shadow-xl")
      expect(classes).to include("z-50")
    end
  end

  describe "sidebar classes" do
    it "defines SIDEBAR class" do
      expect(ComponentClasses::SIDEBAR).to include("bg-white")
      expect(ComponentClasses::SIDEBAR).to include("border-l")
    end

    it "defines SIDEBAR_HEADER class" do
      expect(ComponentClasses::SIDEBAR_HEADER).to include("border-b")
    end

    it "defines SIDEBAR_BODY class" do
      expect(ComponentClasses::SIDEBAR_BODY).to include("overflow-y-auto")
    end

    it "defines SIDEBAR_FOOTER class" do
      expect(ComponentClasses::SIDEBAR_FOOTER).to include("border-t")
    end
  end

  describe "section classes" do
    it "defines SECTION_HEADER class" do
      expect(ComponentClasses::SECTION_HEADER).to include("hover:bg-gray-50")
    end

    it "defines SECTION_TITLE class" do
      expect(ComponentClasses::SECTION_TITLE).to include("uppercase")
    end
  end

  describe "close button" do
    it "defines CLOSE_BTN class" do
      expect(ComponentClasses::CLOSE_BTN).to include("hover:text-gray-600")
    end
  end
end
