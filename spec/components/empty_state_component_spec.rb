# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmptyStateComponent, type: :component do
  let(:base_args)   { { title: "No items", description: "Get started by creating your first item." } }
  let(:action_args) { base_args.merge(action_path: "/new", action_text: "Create New") }

  describe "#initialize" do
    it "sets title and description" do
      component = described_class.new(**base_args)
      aggregate_failures do
        expect(component.title).to eq("No items")
        expect(component.description).to eq("Get started by creating your first item.")
      end
    end

    it "sets a default icon path" do
      expect(described_class.new(**base_args).icon_path).to be_present
    end

    it "accepts a custom icon path" do
      custom_path = "M12 4v16m8-8H4"
      expect(described_class.new(**base_args, icon_path: custom_path).icon_path).to eq(custom_path)
    end

    it "accepts action path and text" do
      component = described_class.new(**action_args)
      aggregate_failures do
        expect(component.action_path).to eq("/new")
        expect(component.action_text).to eq("Create New")
      end
    end
  end

  describe "#render_action?" do
    it "returns true when both action_path and action_text are present" do
      expect(described_class.new(**action_args).render_action?).to be true
    end

    it "returns false when action_path is missing" do
      expect(described_class.new(**base_args, action_text: "Create New").render_action?).to be false
    end

    it "returns false when action_text is missing" do
      expect(described_class.new(**base_args, action_path: "/new").render_action?).to be false
    end

    it "returns false when both are missing" do
      expect(described_class.new(**base_args).render_action?).to be false
    end
  end

  describe "rendering" do
    it "renders title, description, icon, and container styling" do
      render_inline(described_class.new(title: "No flowcharts yet", description: "Get started by creating."))
      aggregate_failures do
        expect(page).to have_css("h3", text: "No flowcharts yet")
        expect(page).to have_css("p", text: "Get started by creating.")
        expect(page).to have_css("svg")
        expect(page).to have_css(".card")
      end
    end

    it "renders action button when action is provided" do
      render_inline(described_class.new(**action_args))
      aggregate_failures do
        expect(page).to have_link("Create New", href: "/new")
        expect(page).to have_css("a.btn-primary")
      end
    end

    it "does not render action button when action is not provided" do
      render_inline(described_class.new(**base_args))
      expect(page).not_to have_css("a.btn-primary")
    end
  end
end
