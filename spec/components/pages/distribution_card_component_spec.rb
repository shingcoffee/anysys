# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::DistributionCardComponent, type: :component do
  subject(:component) { described_class.new(page: page_record, customer_id: 12_345_678) }

  def render_component
    with_request_url("/12345678/admin/maintenance/pages/1", host: "www.example.com") do
      render_inline(component)
    end
  end

  def audience_switch(key)
    page.find("input[type='checkbox'][value='#{key}']", visible: :all)
  end

  let(:published_all_visible) do
    build_stubbed(:page, :for_member, :for_public, :launched, customer_id: 12_345_678,
                   public_uuid: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
  end

  let(:published_member_visible) do
    build_stubbed(:page, :for_member, :launched, customer_id: 12_345_678,
                   public_uuid: "11111111-2222-4333-8444-555555555555")
  end

  let(:unpublished_page) do
    build_stubbed(:page, :for_member, :for_public, customer_id: 12_345_678, launched: false,
                   public_uuid: "99999999-8888-4777-8666-555555555555")
  end

  let(:admin_only_page) do
    build_stubbed(:page, :launched, customer_id: 12_345_678,
                   public_uuid: "12345678-1234-4234-8234-123456789012")
  end

  let(:member_only_page) do
    build_stubbed(:page, :member_only, :launched, customer_id: 12_345_678,
                   public_uuid: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeee01")
  end

  let(:public_only_page) do
    build_stubbed(:page, :public_only, :launched, customer_id: 12_345_678,
                   public_uuid: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeee02")
  end

  describe "return_to and turbo_frame options" do
    let(:page_record) { published_all_visible }
    subject(:component) do
      described_class.new(
        page: page_record,
        customer_id: 12_345_678,
        return_to: "/12345678/admin/pages/1",
        turbo_frame: "page-publishing"
      )
    end

    before { render_component }

    it "includes a hidden return_to field and turbo-frame on the visibility form" do
      expect(page).to have_field("return_to", type: :hidden, with: "/12345678/admin/pages/1")
      expect(page).to have_css("form[data-controller='page-visibility tooltip'][data-turbo-frame='page-publishing']")
    end

    it "passes return_to on the take-offline form" do
      form = page.find("form[action*='/launch']")
      expect(form).to have_field("return_to", type: :hidden, with: "/12345678/admin/pages/1")
      expect(form["data-turbo-frame"]).to eq("page-publishing")
    end
  end

  describe "default rendering" do
    let(:page_record) { published_all_visible }

    before { render_component }

    it "renders the card wrapper" do
      expect(page).to have_css("div.card")
    end

    it "renders the unified 'Publishing & access' heading" do
      expect(page).to have_text("Publishing & access")
    end

    it "renders the Who can open section label" do
      expect(page).to have_text("Who can open")
    end

    it "renders all three audience rows" do
      expect(page).to have_text("Admin")
      expect(page).to have_text("Member")
      expect(page).to have_text("Public")
    end

    it "does not render a Save visibility submit button (auto-saves on change)" do
      expect(page).not_to have_button("Save visibility")
    end

    it "wires the saving and last-audience Stimulus values" do
      form = page.find("form[data-controller='page-visibility tooltip']")
      expect(form["data-page-visibility-saving-value"]).to eq("Saving…")
      expect(form["data-page-visibility-last-audience-value"]).to eq("A form needs at least one audience.")
    end

    it "renders a live status target for auto-save feedback" do
      expect(page).to have_css("[data-page-visibility-target='status'][aria-live='polite']")
    end

    it "does not show Always on or a Visible caption beside the switches" do
      expect(page).not_to have_text("Always on")
      expect(page).not_to have_css("span.text-caption", text: "Visible")
    end
  end

  describe "publishing controls — launched page" do
    let(:page_record) { published_all_visible }

    before { render_component }

    it "shows the launched badge" do
      expect(page).to have_text("Launched")
    end

    it "renders Take Offline" do
      expect(page).to have_button("Take Offline")
    end

    it "does not render Launch" do
      expect(page).not_to have_button("Launch")
    end

    it "renders the public URL with a copy control" do
      expect(page).to have_css("a[href*='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee']")
      expect(page).to have_css("[data-controller='click-to-copy']")
      expect(page).to have_button("Copy")
    end
  end

  describe "publishing controls — draft page" do
    let(:page_record) { unpublished_page }

    before { render_component }

    it "shows the not launched badge" do
      expect(page).to have_text("Not launched")
    end

    it "renders Launch" do
      expect(page).to have_button("Launch")
    end

    it "does not render Take Offline" do
      expect(page).not_to have_button("Take Offline")
    end

    it "shows the launch-to-generate message" do
      expect(page).to have_text("Launch this page to generate a public URL.")
    end
  end

  describe "switch group" do
    let(:page_record) { published_all_visible }

    before { render_component }

    it "renders exactly three checkboxes as track switches" do
      checkboxes = page.all("input[type='checkbox']", visible: :all)
      expect(checkboxes.count).to eq(3)
      expect(page).to have_css("input.sr-only.peer[type='checkbox']", count: 3, visible: :all)
    end

    it "does not render any radio inputs" do
      expect(page).not_to have_css("input[type='radio']", visible: :all)
    end

    it "posts a hidden field for every currently checked audience" do
      %w[admin member public].each do |key|
        expect(page).to have_css("input[type='hidden'][name='page[visible_audiences][]'][value='#{key}']", visible: :all)
      end
    end
  end

  describe "exact audience set — admin only" do
    let(:page_record) { admin_only_page }

    before { render_component }

    it "checks only admin and locks it as the last audience" do
      expect(audience_switch("admin")[:checked]).to be_truthy
      expect(audience_switch("admin")[:disabled]).to be_truthy
      expect(audience_switch("admin")["aria-label"]).to eq("A form needs at least one audience.")
      expect(audience_switch("admin").find(:xpath, "..")["data-tooltip"]).to eq("A form needs at least one audience.")
      expect(audience_switch("member")[:checked]).to be_falsy
      expect(audience_switch("member")[:disabled]).to be_falsy
      expect(audience_switch("public")[:checked]).to be_falsy
    end
  end

  describe "exact audience set — admin + member" do
    let(:page_record) { published_member_visible }

    before { render_component }

    it "checks admin and member, leaves public off, and does not lock admin" do
      expect(audience_switch("admin")[:checked]).to be_truthy
      expect(audience_switch("admin")[:disabled]).to be_falsy
      expect(audience_switch("member")[:checked]).to be_truthy
      expect(audience_switch("public")[:checked]).to be_falsy
    end
  end

  describe "exact audience set — all three" do
    let(:page_record) { published_all_visible }

    before { render_component }

    it "checks every audience and leaves every switch enabled" do
      %w[admin member public].each do |key|
        expect(audience_switch(key)[:checked]).to be_truthy
        expect(audience_switch(key)[:disabled]).to be_falsy
      end
    end
  end

  describe "exact audience set — member only" do
    let(:page_record) { member_only_page }

    before { render_component }

    it "checks only member and locks that switch" do
      expect(audience_switch("admin")[:checked]).to be_falsy
      expect(audience_switch("member")[:checked]).to be_truthy
      expect(audience_switch("member")[:disabled]).to be_truthy
      expect(audience_switch("public")[:checked]).to be_falsy
    end
  end

  describe "exact audience set — public only" do
    let(:page_record) { public_only_page }

    before { render_component }

    it "checks only public and locks that switch" do
      expect(audience_switch("admin")[:checked]).to be_falsy
      expect(audience_switch("member")[:checked]).to be_falsy
      expect(audience_switch("public")[:checked]).to be_truthy
      expect(audience_switch("public")[:disabled]).to be_truthy
    end
  end

  describe "Stimulus page-visibility controller wiring" do
    let(:page_record) { published_all_visible }

    before { render_component }

    it "form carries page-visibility and tooltip controllers" do
      expect(page).to have_css("form[data-controller='page-visibility tooltip']")
    end

    it "wires each audience switch as a target that syncs on change" do
      %w[admin member public].each do |key|
        switch = audience_switch(key)
        expect(switch["data-page-visibility-target"]).to eq(key)
        expect(switch["data-action"]).to eq("change->page-visibility#sync")
      end
    end
  end

  describe "visibility form" do
    let(:page_record) { published_all_visible }

    before { render_component }

    it "targets the visibility PATCH URL" do
      form = page.find("form[data-controller='page-visibility tooltip']")
      expect(form["action"]).to include("/admin/maintenance/pages/")
      expect(form["action"]).to include("/visibility")
    end

    it "uses PATCH method" do
      form = page.find("form[data-controller='page-visibility tooltip']")
      method_input = form.find("input[name='_method']", visible: :all)
      expect(method_input[:value].downcase).to eq("patch")
    end
  end

  describe "enabled state — launched, all audiences" do
    let(:page_record) { published_all_visible }

    before { render_component }

    it "renders three Open links" do
      expect(page).to have_css("a", text: "Open", count: 3)
    end

    it "all Open links carry target=_blank and rel=noopener noreferrer" do
      page.all("a", text: "Open").each do |link|
        expect(link["target"]).to eq("_blank")
        expect(link["rel"]).to eq("noopener noreferrer")
      end
    end

    it "admin Open link href includes /render" do
      admin_href = page.all("a", text: "Open").map { |l| l["href"] }.find { |h| h.include?("/render") }
      expect(admin_href).to include("/admin/maintenance/pages/")
      expect(admin_href).to include("/render")
    end

    it "member Open link href includes /member/pages/" do
      member_href = page.all("a", text: "Open").map { |l| l["href"] }.find { |h| h.include?("/member/pages/") }
      expect(member_href).to include("/member/pages/")
    end

    it "public Open link href includes the public uuid" do
      public_href = page.all("a", text: "Open").map { |l| l["href"] }.find { |h| h.include?("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee") }
      expect(public_href).to include("/page/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
    end

    it "renders a URL row for each enabled audience" do
      expect(page).to have_css("a[href*='/render']", minimum: 2)
      expect(page).to have_css("a[href*='/member/pages/']", minimum: 2)
      expect(page).to have_css("a[href*='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee']", minimum: 2)
    end

    it "does not render any disabled reason text" do
      expect(page).not_to have_text("Not launched")
      expect(page).not_to have_text("Not visible to")
    end
  end

  describe "enabled state — launched, admin + member" do
    let(:page_record) { published_member_visible }

    before { render_component }

    it "renders two Open links (admin and member) and no public URL row" do
      expect(page).to have_css("a", text: "Open", count: 2)
      expect(page).not_to have_css("a[href*='11111111-2222-4333-8444-555555555555']")
      expect(page).not_to have_text("Not visible to")
      expect(page).not_to have_text("Not launched")
    end
  end

  describe "disabled state — unpublished page" do
    let(:page_record) { unpublished_page }

    before { render_component }

    it "renders no Open anchor links" do
      expect(page).not_to have_css("a", text: "Open")
    end

    it "shows 'Not launched' reason for every enabled audience" do
      expect(page.all("span", text: /Not launched/).count).to be >= 3
    end

    it "does not render any /render or /member/pages/ links" do
      expect(page).not_to have_css("a[href*='/render']")
      expect(page).not_to have_css("a[href*='/member/pages/']")
    end
  end

  describe "disabled state — launched, admin only" do
    let(:page_record) { admin_only_page }

    before { render_component }

    it "renders exactly one Open link (admin only) and no off-row captions" do
      expect(page).to have_css("a", text: "Open", count: 1)
      expect(page.find("a", text: "Open")["href"]).to include("/admin/maintenance/pages/")
      expect(page).not_to have_text("Not visible to")
      expect(page).not_to have_text("Not launched")
    end
  end

  describe "action key" do
    let(:page_record) { published_all_visible }

    before { render_component }

    it "renders the action key input with format help" do
      expect(page).to have_field("page[action_key]")
      expect(page).to have_css("input[name='page[action_key]'][data-action='change->page-visibility#sync']")
      expect(page).to have_css("#page-action-key-help", text: "Start with a letter. Use only lowercase letters, numbers and underscores.")
      expect(page).not_to have_text("Action URL")
      expect(page).not_to have_text("Other pages in this action")
    end
  end

  describe "action key — saved value" do
    let(:page_record) do
      build_stubbed(:page, :for_member, :launched, customer_id: 12_345_678, action_key: "enroll",
                     public_uuid: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeee03")
    end

    before { render_component }

    it "shows the Action URL and an empty siblings caption" do
      expect(page).to have_field("page[action_key]", with: "enroll")
      expect(page).to have_link(href: "http://www.example.com/12345678/actions/enroll")
      expect(page).to have_text("Other pages in this action")
      expect(page).to have_text("No other pages share this action yet.")
    end
  end

  describe "siblings list" do
    let(:page_record) do
      build_stubbed(:page, :public_only, :launched, customer_id: 12_345_678, action_key: "enroll",
                     public_uuid: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeee04")
    end
    let(:sibling) do
      build_stubbed(:page, :for_member, :launched, customer_id: 12_345_678, name: "Enroll (member)")
    end
    let(:offline_sibling) do
      build_stubbed(:page, :member_only, customer_id: 12_345_678, name: "Public enroll", launched: false)
    end

    before do
      allow(Pages::ActionResolver).to receive(:siblings).with(page_record).and_return([sibling, offline_sibling])
      render_component
    end

    it "lists other pages' names, audiences, and offline caption" do
      expect(page).to have_link("Enroll (member)", href: /\/admin\/maintenance\/pages\/#{sibling.id}/)
      expect(page).to have_link("Public enroll", href: /\/admin\/maintenance\/pages\/#{offline_sibling.id}/)
      expect(page).to have_css(".badge", text: "Admin")
      expect(page).to have_css(".badge", text: "Member")
      expect(page).to have_text("Not launched")
      expect(page).not_to have_text("No other pages share this action yet.")
    end
  end

  describe "audience dot classes" do
    let(:page_record) { published_all_visible }

    before { render_component }

    it "renders a colored dot for each audience" do
      expect(page).to have_css("span.rounded-full.bg-accent")
      expect(page).to have_css("span.rounded-full.bg-member-accent")
      expect(page).to have_css("span.rounded-full.bg-success")
    end
  end

  describe "publishing_editable: false" do
    let(:page_record) { published_all_visible }
    subject(:component) do
      described_class.new(page: page_record, customer_id: 12_345_678, publishing_editable: false)
    end

    before { render_component }

    it "hides Launch and Take Offline" do
      expect(page).not_to have_button("Launch")
      expect(page).not_to have_button("Take Offline")
    end

    it "renders visibility switches and the action key as read-only" do
      expect(page).to have_css("input[type='checkbox'][disabled]", count: 3, visible: :all)
      expect(page).not_to have_css("form[data-controller='page-visibility tooltip']")
      expect(page).to have_css("input[name='page[action_key]'][readonly]")
    end
  end

  describe "preferred public alias" do
    let(:page_record) { published_all_visible }

    it "uses the request origin and mount prefix for the sharing and Public Open addresses" do
      with_request_url("/12345678/admin/maintenance/pages/1", host: "forms.example.com") do
        vc_test_controller.request.script_name = "/app"
        allow(PageShortcuts::PublicPath).to receive(:public_page)
          .with(page: page_record, customer_id: 12_345_678, host: "forms.example.com").and_return("/campaign/register")
        render_inline(component)
      end
      expect(page).to have_link(href: "http://forms.example.com/app/campaign/register", count: 3)
      expect(page).to have_no_css("a[href*='/page/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee']")
    end
  end
end
