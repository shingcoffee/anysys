# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::CountableItemsFormComponent, type: :component do
  # Sample items with explicit positions to verify sort order.
  # item_page has position 1 (lower) so it should appear first in the list.
  let(:item_page) do
    double(
      "CountableItem",
      id:          2,
      key:         "page",
      label:       "Pages",
      description: "Published pages",
      unit:        "pages",
      category:    "Content",
      period:      "total",
      enabled?:    false,
      position:    1
    )
  end

  let(:item_email) do
    double(
      "CountableItem",
      id:          1,
      key:         "entity",
      label:       "Emails",
      description: "Total emails sent",
      unit:        "emails",
      category:    "Communications",
      period:      "monthly",
      enabled?:    true,
      position:    2
    )
  end

  # Deliberately pass items in reverse position order to verify the component sorts them.
  let(:items) { [item_email, item_page] }

  before do
    stub_helpers = double(
      "helpers",
      admin_maintenance_platform_billing_countable_items_path: "/81721200/admin/maintenance/platform/billing/countable_items",
      protect_against_forgery?: false
    )
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)

    render_inline(described_class.new(items: items, customer_id: "81721200"))
  end

  # ─── Form action & method ─────────────────────────────────────────────────

  describe "form action and method" do
    it "renders a form targeting the countable_items path" do
      expect(page).to have_css(
        "form[action='/81721200/admin/maintenance/platform/billing/countable_items']"
      )
    end

    it "uses the PATCH method override" do
      expect(page).to have_css("input[name='_method'][value='patch']", visible: :hidden)
    end
  end

  # ─── Sort order ───────────────────────────────────────────────────────────

  describe "sort order" do
    it "renders items sorted by position ascending (item_page position=1 before item_email position=2)" do
      # The 'page' key badge (position 1) should appear before 'email' key badge (position 2)
      # in the DOM. We check the rendered text order.
      rendered_html = page.native.to_s
      page_idx  = rendered_html.index("key-badge-page")
      email_idx = rendered_html.index("key-badge-entity")
      expect(page_idx).to be < email_idx
    end
  end

  # ─── Stimulus controller wiring ───────────────────────────────────────────

  describe "Stimulus reorder controller" do
    it "wires the countable-items-reorder controller on the list element" do
      expect(page).to have_css("ol[data-controller='countable-items-reorder']")
    end

    it "marks each row with the Stimulus row target" do
      expect(page).to have_css(
        "li[data-countable-items-reorder-target='row']", count: 2
      )
    end

    it "renders a drag handle with the Stimulus handle target on each row" do
      expect(page).to have_css(
        "button[data-countable-items-reorder-target='handle']", count: 2
      )
    end

    it "renders an Up button with the correct action on each row" do
      expect(page).to have_css(
        "button[data-countable-items-reorder-target='upButton'][data-action='click->countable-items-reorder#moveUp']",
        count: 2
      )
    end

    it "renders a Down button with the correct action on each row" do
      expect(page).to have_css(
        "button[data-countable-items-reorder-target='downButton'][data-action='click->countable-items-reorder#moveDown']",
        count: 2
      )
    end

    it "renders the position label target on each row" do
      expect(page).to have_css(
        "[data-countable-items-reorder-target='positionLabel']", count: 2
      )
    end
  end

  # ─── Key badge (read-only, not an editable input) ─────────────────────────

  describe "item key badge" do
    it "renders the key-badge testid for item_page" do
      expect(page).to have_css("[data-testid='key-badge-page']")
    end

    it "renders the key-badge testid for item_email" do
      expect(page).to have_css("[data-testid='key-badge-entity']")
    end

    it "shows the key text inside the badge for item_page" do
      expect(page).to have_css("[data-testid='key-badge-page']", text: "page")
    end

    it "shows the key text inside the badge for item_email" do
      expect(page).to have_css("[data-testid='key-badge-entity']", text: "entity")
    end

    it "uses the item label as the row title and the key as a caption" do
      expect(page).to have_css("p.font-medium", text: "Pages")
      expect(page).to have_css("p.font-mono", text: "page")
    end

    it "does NOT render an editable input field named for key" do
      expect(page).not_to have_css("input[name='items[0][key]']")
      expect(page).not_to have_css("input[name='items[1][key]']")
    end

    it "does NOT render a textarea named for key" do
      expect(page).not_to have_css("textarea[name*='[key]']")
    end
  end

  # ─── Hidden id fields ─────────────────────────────────────────────────────

  describe "hidden id fields" do
    # item_page (position=1) sorts first → index 0; item_email (position=2) → index 1
    it "includes a hidden id field for the first sorted item (item_page)" do
      expect(page).to have_css("input[type='hidden'][name='items[0][id]'][value='2']", visible: :hidden)
    end

    it "includes a hidden id field for the second sorted item (item_email)" do
      expect(page).to have_css("input[type='hidden'][name='items[1][id]'][value='1']", visible: :hidden)
    end
  end

  # ─── Hidden position inputs ───────────────────────────────────────────────

  describe "hidden position inputs" do
    it "renders a hidden position input for each row with the Stimulus positionInput target" do
      expect(page).to have_css(
        "input[data-countable-items-reorder-target='positionInput']",
        count: 2, visible: :hidden
      )
    end

    it "renders a position input with name items[0][position] for the first sorted row" do
      expect(page).to have_css(
        "input[name='items[0][position]']", visible: :hidden
      )
    end

    it "renders a position input with name items[1][position] for the second sorted row" do
      expect(page).to have_css(
        "input[name='items[1][position]']", visible: :hidden
      )
    end
  end

  # ─── Label inputs ─────────────────────────────────────────────────────────

  describe "label text inputs" do
    # item_page sorts first (position=1 → idx 0), item_email is idx 1
    it "renders a label input for item_page (idx 0) with correct name and value" do
      expect(page).to have_field("items[0][label]", with: "Pages")
    end

    it "renders a label input for item_email (idx 1) with correct name and value" do
      expect(page).to have_field("items[1][label]", with: "Emails")
    end

    it "includes aria-label on the label input for item_page" do
      expect(page).to have_css("input[name='items[0][label]'][aria-label='Label for page']")
    end

    it "includes aria-label on the label input for item_email" do
      expect(page).to have_css("input[name='items[1][label]'][aria-label='Label for entity']")
    end
  end

  # ─── Description textareas ────────────────────────────────────────────────

  describe "description textarea inputs" do
    it "renders a description textarea for item_page with correct name" do
      expect(page).to have_css("textarea[name='items[0][description]']")
    end

    it "renders the description value for item_page" do
      expect(page).to have_css("textarea[name='items[0][description]']", text: "Published pages")
    end

    it "renders a description textarea for item_email with correct name" do
      expect(page).to have_css("textarea[name='items[1][description]']")
    end

    it "includes aria-label on description textarea for item_page" do
      expect(page).to have_css("textarea[name='items[0][description]'][aria-label='Description for page']")
    end
  end

  # ─── Unit inputs ──────────────────────────────────────────────────────────

  describe "unit text inputs" do
    it "renders a unit input for item_page with correct name and value" do
      expect(page).to have_field("items[0][unit]", with: "pages")
    end

    it "renders a unit input for item_email with correct name and value" do
      expect(page).to have_field("items[1][unit]", with: "emails")
    end

    it "includes aria-label on unit input" do
      expect(page).to have_css("input[name='items[0][unit]'][aria-label='Unit for page']")
    end
  end

  # ─── Category selects ─────────────────────────────────────────────────────

  describe "category select inputs" do
    it "renders a category select for item_page" do
      expect(page).to have_css("select[name='items[0][category]']")
    end

    it "has exactly 6 category options for item_page" do
      expect(page).to have_css("select[name='items[0][category]'] option", count: 6)
    end

    it "includes all six expected category options" do
      %w[Content Communications Commerce Platform Storage Support].each do |cat|
        expect(page).to have_css("select[name='items[0][category]'] option[value='#{cat}']")
      end
    end

    it "preselects the item's current category (Content for item_page)" do
      expect(page).to have_css(
        "select[name='items[0][category]'] option[value='Content'][selected]"
      )
    end

    it "preselects the item's current category (Communications for item_email)" do
      expect(page).to have_css(
        "select[name='items[1][category]'] option[value='Communications'][selected]"
      )
    end

    it "includes aria-label on category select" do
      expect(page).to have_css("select[name='items[0][category]'][aria-label='Category for page']")
    end
  end

  # ─── Period selects ───────────────────────────────────────────────────────

  describe "period select inputs" do
    it "renders a period select for item_page" do
      expect(page).to have_css("select[name='items[0][period]']")
    end

    it "has exactly 2 period options" do
      expect(page).to have_css("select[name='items[0][period]'] option", count: 2)
    end

    it "includes both period options (total and monthly)" do
      expect(page).to have_css("select[name='items[0][period]'] option[value='total']")
      expect(page).to have_css("select[name='items[0][period]'] option[value='monthly']")
    end

    it "preselects 'total' for item_page" do
      expect(page).to have_css(
        "select[name='items[0][period]'] option[value='total'][selected]"
      )
    end

    it "preselects 'monthly' for item_email" do
      expect(page).to have_css(
        "select[name='items[1][period]'] option[value='monthly'][selected]"
      )
    end

    it "includes aria-label on period select" do
      expect(page).to have_css("select[name='items[0][period]'][aria-label='Period for page']")
    end
  end

  # ─── Enabled checkboxes ───────────────────────────────────────────────────

  describe "enabled checkboxes" do
    # item_page (idx 0) is disabled; item_email (idx 1) is enabled
    it "renders the hidden false companion before the checkbox for item_page" do
      expect(page).to have_css("input[type='hidden'][name='items[0][enabled]'][value='false']", visible: :hidden)
    end

    it "renders an unchecked enabled checkbox for item_page (enabled? false)" do
      expect(page).to have_css("input[type='checkbox'][name='items[0][enabled]'][value='true']")
      expect(page).not_to have_css("input[type='checkbox'][name='items[0][enabled]'][checked]")
    end

    it "renders a checked enabled checkbox for item_email (enabled? true)" do
      expect(page).to have_css("input[type='checkbox'][name='items[1][enabled]'][checked]")
    end

    it "includes aria-label on enabled checkboxes" do
      expect(page).to have_css("input[type='checkbox'][name='items[0][enabled]'][aria-label='Enabled for page']")
    end
  end

  # ─── Submit button ────────────────────────────────────────────────────────

  describe "submit button" do
    it "renders a single Save Changes button" do
      expect(page).to have_button("Save Changes")
    end
  end

  describe "row chrome" do
    it "does not tint enabled rows with an accent background" do
      expect(page.native.to_s).not_to include("has-[:checked]:bg-accent-subtle")
    end

    it "dims disabled row fields" do
      expect(page).to have_css("li[data-countable-items-reorder-target='row'] .item-fields.opacity-60", count: 2)
    end
  end

  it "lists every countable item so each one can be toggled" do
    storage = double(key: "storage", position: 3)
    component = described_class.new(items: items + [storage], customer_id: 81721200)
    expect(component.sorted_items.map(&:key)).to eq(%w[page entity storage])
  end
end
