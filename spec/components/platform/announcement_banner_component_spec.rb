# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::AnnouncementBannerComponent, type: :component do
  include Rails.application.routes.url_helpers

  let(:customer) { create(:customer, name: "Acme") }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:member) { create(:user, :member, customer: customer) }
  let(:owner) { double("platform_owner", admin?: false, platform_owner?: true) }
  let(:dismiss_url) { "/#{customer.id}/admin/platform_announcement_dismissals" }

  after { Current.reset }

  def build_component(user:, **opts)
    described_class.new(user: user, customer_id: customer.id, dismissed_ids: [], **opts)
  end

  before do
    allow_any_instance_of(described_class).to receive(:dismiss_path).and_return(dismiss_url)
  end

  describe "#render?" do
    it "returns false for a member even when a live row exists" do
      create(:platform_announcement, :published)
      expect(build_component(user: member).render?).to be false
    end

    it "returns false when there is no signed-in viewer" do
      create(:platform_announcement, :published)
      expect(build_component(user: nil).render?).to be false
    end

    it "returns true for an admin so the Turbo Stream dismiss target stays in the DOM" do
      create(:platform_announcement, :draft)
      expect(build_component(user: admin).render?).to be true
    end

    it "returns true for a platform owner" do
      create(:platform_announcement, :published)
      expect(build_component(user: owner).render?).to be true
    end
  end

  describe "rendering" do
    it "renders the English body by default" do
      create(:platform_announcement, :published, body_en: "We will be down for maintenance.")
      render_inline(build_component(user: admin))

      expect(page).to have_text("We will be down for maintenance.")
      expect(page).to have_css('[role="status"]')
    end

    it "renders the Chinese body when the locale is zh-CN" do
      create(:platform_announcement, :published, body_zh: "系统将进行维护。")
      I18n.with_locale(:"zh-CN") do
        render_inline(build_component(user: admin))
      end

      expect(page).to have_text("系统将进行维护。")
    end

    it "renders the title alongside the body" do
      create(:platform_announcement, :published, title: "Scheduled maintenance", body_en: "Back at 02:00 UTC.")
      render_inline(build_component(user: admin))

      expect(page).to have_text("Scheduled maintenance")
      expect(page).to have_text("Back at 02:00 UTC.")
    end

    it "keeps the full notice text in the DOM with length limits for expand/fold" do
      create(:platform_announcement, :published, title: "Scheduled maintenance", body_en: "We will be down for maintenance.")
      render_inline(build_component(user: admin))

      expect(page).to have_css("[data-controller='text-expand'][data-action*='text-expand#toggle']")
      expect(page).to have_css("[data-text-expand-target='clamped'][data-limit='#{described_class::TITLE_LIMIT}']", text: "Scheduled maintenance")
      expect(page).to have_css("[data-text-expand-target='clamped'][data-limit='#{described_class::BODY_LIMIT}']", text: "We will be down for maintenance.")
    end

    it "stacks every live notice as its own dismissible strip" do
      create(:platform_announcement, :published, body_en: "Oldest notice")
      create(:platform_announcement, :published, body_en: "Middle notice")
      create(:platform_announcement, :published, body_en: "Newest notice")
      render_inline(build_component(user: admin))

      expect(page).to have_text("Newest notice")
      expect(page).to have_text("Middle notice")
      expect(page).to have_text("Oldest notice")
      expect(page).to have_css("form[action='#{dismiss_url}']", count: 3)
    end

    it "caps the visible stack at MAX_VISIBLE so the shell is not pushed off-screen" do
      (described_class::MAX_VISIBLE + 2).times { |i| create(:platform_announcement, :published, body_en: "Notice #{i}") }
      render_inline(build_component(user: admin))

      expect(page).to have_css("form[action='#{dismiss_url}']", count: described_class::MAX_VISIBLE)
    end

    it "orders critical above warning above info regardless of recency" do
      create(:platform_announcement, :published, :critical, body_en: "Critical notice")
      create(:platform_announcement, :published, :warning, body_en: "Warning notice")
      create(:platform_announcement, :published, :info, body_en: "Info notice")
      render_inline(build_component(user: admin))

      bodies = page.all("[role='alert'], [role='status']").map(&:text)
      expect(bodies.first).to include("Critical notice")
      expect(bodies.last).to include("Info notice")
    end

    it "renders the stack wrapper even with nothing live, so a dismiss can retarget it" do
      create(:platform_announcement, :draft)
      render_inline(build_component(user: admin))

      expect(page).to have_css("##{described_class::STACK_DOM_ID}")
      expect(page).not_to have_css("form[action='#{dismiss_url}']")
    end

    it "gives every strip a stable id derived from the announcement" do
      announcement = create(:platform_announcement, :published)
      render_inline(build_component(user: admin))

      expect(page).to have_css("##{described_class::STACK_DOM_ID}-#{announcement.id}")
    end

    it "applies info severity classes" do
      create(:platform_announcement, :published, :info)
      render_inline(build_component(user: admin))

      expect(page).to have_css(".bg-info-subtle[role='status']")
      expect(page).to have_css(".border-info")
    end

    it "applies warning severity classes" do
      create(:platform_announcement, :published, :warning)
      render_inline(build_component(user: admin))

      expect(page).to have_css(".bg-warning-subtle[role='status']")
      expect(page).to have_css(".border-warning")
    end

    it "applies critical severity classes" do
      create(:platform_announcement, :published, :critical)
      render_inline(build_component(user: admin))

      expect(page).to have_css(".bg-danger-subtle[role='alert']")
      expect(page).to have_css(".border-danger")
    end

    it "renders Learn more when link_url is present" do
      create(:platform_announcement, :published, link_url: "https://status.example.com")
      render_inline(build_component(user: admin))

      expect(page).to have_link("Learn more", href: "https://status.example.com")
      expect(page).to have_css('a[target="_blank"][rel="noopener noreferrer"]', text: "Learn more")
    end

    it "omits Learn more when link_url is blank" do
      create(:platform_announcement, :published, link_url: nil)
      render_inline(build_component(user: admin))

      expect(page).not_to have_link("Learn more")
    end

    it "labels the dismiss control with the announcement title for screen readers" do
      announcement = create(:platform_announcement, :published, title: "Scheduled maintenance")
      render_inline(build_component(user: admin))

      expect(page).to have_css("button[aria-label='Dismiss announcement: Scheduled maintenance']")
      expect(page).to have_css("form[action='#{dismiss_url}']")
      expect(page).to have_field("platform_announcement_id", type: :hidden, with: announcement.id.to_s)
    end

    it "renders nothing when render? is false" do
      render_inline(build_component(user: member))
      expect(page.native.inner_html).to be_empty
    end
  end
end
