# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::AnnouncementFormComponent, type: :component do
  include Rails.application.routes.url_helpers

  let(:index_url) { "/81721200/admin/maintenance/platform/announcements" }
  let(:create_url) { index_url }

  let(:new_announcement) { PlatformAnnouncement.new }

  let(:persisted_announcement) do
    create(
      :platform_announcement,
      :selected,
      title: "Q3 downtime",
      body_en: "English body",
      body_zh: "中文正文",
      severity: "warning",
      status: "published",
      link_url: "https://status.example.com",
      target_rules: {
        "type" => "group",
        "joins" => [],
        "conditions" => [
          { "field" => "name", "operator" => "equals", "value" => "Acme Corp" }
        ]
      }
    )
  end

  def build_component(announcement, **opts)
    described_class.new(
      announcement: announcement,
      customer_id: opts.fetch(:customer_id, "81721200")
    )
  end

  before do
    allow_any_instance_of(described_class).to receive(:form_url).and_return(create_url)
    allow_any_instance_of(described_class).to receive(:index_path).and_return(index_url)
  end

  describe "new announcement form" do
    before { render_inline(build_component(new_announcement)) }

    it "renders the Content, Display, and Audience cards" do
      expect(page).to have_css("h2", text: "Content")
      expect(page).to have_css("h2", text: "Display")
      expect(page).to have_css("h2", text: "Audience")
    end

    it "renders required fields and the create submit" do
      expect(page).to have_field("platform_announcement[title]")
      expect(page).to have_field("platform_announcement[body_en]")
      expect(page).to have_field("platform_announcement[body_zh]")
      expect(page).to have_field("platform_announcement[link_url]")
      expect(page).to have_select("platform_announcement[severity]")
      expect(page).to have_select("platform_announcement[status]")
      expect(page).to have_field("platform_announcement[starts_at]")
      expect(page).to have_field("platform_announcement[ends_at]")
      expect(page).to have_button("Create announcement")
      expect(page).to have_link("Cancel", href: index_url)
    end

    it "defaults audience to all and hides the condition builder" do
      expect(page).to have_checked_field("platform_announcement[audience]", with: "all")
      expect(page).to have_css('[data-platform-announcement-audience-target="panel"].hidden')
    end

    it "wires audience radios to the audience controller and mounts the segment builder" do
      expect(page).to have_css('[data-controller="platform-announcement-audience"]')
      expect(page).to have_css('[data-action="change->platform-announcement-audience#toggleAudience"]', count: 2)
      expect(page).to have_css('[data-controller="segment-builder"]')
      expect(page).to have_css('input[name="platform_announcement[target_rules_json]"]', visible: :all)
      fields_json = page.find("[data-controller='segment-builder']", visible: :all)["data-segment-builder-fields-value"]
      expect(fields_json).to include('"name"')
      expect(fields_json).to include('"tier"')
    end
  end

  describe "edit announcement form" do
    before { render_inline(build_component(persisted_announcement)) }

    it "renders Save changes and keeps posted values" do
      expect(page).to have_button("Save changes")
      expect(page).to have_field("platform_announcement[title]", with: "Q3 downtime")
      expect(page).to have_field("platform_announcement[body_en]", with: "English body")
      expect(page).to have_select("platform_announcement[severity]", selected: "Warning")
    end

    it "shows the condition builder with the stored rules" do
      expect(page).to have_checked_field("platform_announcement[audience]", with: "selected")
      expect(page).not_to have_css('[data-platform-announcement-audience-target="panel"].hidden')
      output = page.find('input[name="platform_announcement[target_rules_json]"]', visible: :all).value
      parsed = JSON.parse(output)
      expect(parsed["conditions"].first["field"]).to eq("name")
      expect(parsed["conditions"].first["value"]).to eq("Acme Corp")
    end
  end

  describe "validation errors" do
    it "renders AlertComponent with the full error sentence" do
      announcement = PlatformAnnouncement.new
      announcement.errors.add(:title, "can't be blank")
      announcement.errors.add(:body_en, "can't be blank")
      render_inline(build_component(announcement))

      expect(page).to have_text(announcement.errors.full_messages.to_sentence)
    end
  end

  describe "form_method" do
    it "returns :post for a new record and :patch for a persisted one" do
      expect(build_component(new_announcement).form_method).to eq(:post)
      expect(build_component(persisted_announcement).form_method).to eq(:patch)
    end
  end
end
