# spec/components/admin/maintenance/platform/module_toggle_component_spec.rb
require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleToggleComponent, type: :component do
  def toggle(**opts)
    render_inline(described_class.new(url: "/x", field: "status", on: false, **opts))
  end

  it "renders an off switch as a submittable form" do
    render = toggle(on: false)
    expect(render.css("form").any?).to be(true)
    expect(render.css("button[role=switch][aria-checked=false]").any?).to be(true)
  end

  it "renders a disabled switch without a form when disabled" do
    render = toggle(disabled: true)
    expect(render.css("form").any?).to be(false)
    expect(render.css("button[disabled]").any?).to be(true)
  end

  it "PATCHes with the field by default" do
    render = toggle
    expect(render.css("input[type=hidden][name='_method'][value='patch']").any?).to be(true)
    expect(render.css("input[type=hidden][name='status'][value='1']").any?).to be(true)
  end

  it "submits with http_method and no field input for resource-style endpoints" do
    render = toggle(field: nil, on: true, http_method: :delete)
    expect(render.css("input[type=hidden][name='_method'][value='delete']").any?).to be(true)
    expect(render.css("input[type=hidden]:not([name='_method']):not([name='authenticity_token'])").any?).to be(false)
  end

  it "renders hidden inputs for extra_params" do
    render = toggle(extra_params: { extendable_model: "Payments::Order", another_param: "value" })
    expect(render.css("input[type=hidden][name='extendable_model'][value='Payments::Order']").any?).to be(true)
    expect(render.css("input[type=hidden][name='another_param'][value='value']").any?).to be(true)
  end

  it "renders no extra hidden inputs when extra_params is empty" do
    render = toggle(extra_params: {})
    # Should only have the field hidden input and the authenticity token from form_with
    expect(render.css("input[type=hidden][name='extendable_model']").any?).to be(false)
    expect(render.css("input[type=hidden][name='another_param']").any?).to be(false)
    # The field input should still exist
    expect(render.css("input[type=hidden][name='status']").any?).to be(true)
  end

  it "renders right-aligned flex container by default" do
    render = toggle
    root_div = render.css("div.flex.items-center.justify-end.gap-3.whitespace-nowrap.flex-shrink-0.ml-auto").first
    expect(root_div).not_to be_nil
  end

  it "renders centered flex container when centered is true" do
    render = toggle(centered: true)
    root_div = render.css("div.flex.items-center.justify-center.gap-3.whitespace-nowrap.flex-shrink-0").first
    expect(root_div).not_to be_nil
    expect(root_div["class"]).not_to include("ml-auto")
  end

  it "renders the label by default when show_label is true" do
    render = toggle(on: true, on_label: "Active")
    expect(render.text).to include("Active")
  end

  it "omits the label when show_label is false" do
    render = toggle(on_label: "Active", show_label: false)
    expect(render.text).not_to include("Active")
  end

  it "omits aria-label when aria_label is blank" do
    render = toggle
    button = render.css("button[role=switch]").first
    expect(button["aria-label"]).to be_nil
  end

  it "passes aria_label through to the switch button" do
    render = toggle(aria_label: "Protect Sign in", show_label: false)
    expect(render.css('button[role=switch][aria-label="Protect Sign in"]').any?).to be(true)
  end

  it "passes aria_label through on a disabled switch" do
    render = toggle(disabled: true, aria_label: "Protect Sign in")
    expect(render.css('button[role=switch][disabled][aria-label="Protect Sign in"]').any?).to be(true)
  end

  it "merges control HTML attributes into an enabled switch" do
    render = toggle(
      aria_label: "Module Status",
      html_attributes: { aria: { describedby: "module-status-reason" }, data: { test_control: "enabled" } }
    )

    expect(render.css('button[role=switch][aria-label="Module Status"][aria-describedby="module-status-reason"][data-test-control="enabled"]').any?).to be(true)
  end

  it "merges control HTML attributes into a disabled switch" do
    render = toggle(
      disabled: true,
      aria_label: "Module Status",
      html_attributes: { aria: { describedby: "module-status-reason" } }
    )

    expect(render.css('button[role=switch][disabled][aria-label="Module Status"][aria-describedby="module-status-reason"]').any?).to be(true)
  end

  # ---------------------------------------------------------------------------
  # data-turbo-confirm regression (fix #3)
  # ---------------------------------------------------------------------------

  describe "confirm: attribute" do
    it "emits data-turbo-confirm on the submit button when confirm: is provided" do
      render = toggle(confirm: "Are you sure you want to toggle this?")
      button = render.css("button[type=submit]").first
      expect(button).not_to be_nil
      expect(button["data-turbo-confirm"]).to eq("Are you sure you want to toggle this?")
    end

    it "does not emit data-turbo-confirm when confirm: is absent" do
      render = toggle
      button = render.css("button[type=submit]").first
      expect(button).not_to be_nil
      expect(button["data-turbo-confirm"]).to be_nil
    end

    it "does not emit data-turbo-confirm when confirm: is nil explicitly" do
      render = toggle(confirm: nil)
      button = render.css("button[type=submit]").first
      expect(button).not_to be_nil
      expect(button["data-turbo-confirm"]).to be_nil
    end

    it "HTML-escapes the confirm string to prevent XSS via the attribute value" do
      malicious = 'Delete <script>alert("xss")</script>'
      render = toggle(confirm: malicious)
      button = render.css("button[type=submit]").first
      # Nokogiri decodes HTML entities from attributes, so the stored value must
      # equal the original string (ERB auto-escaping encodes on write, decoded on read).
      expect(button["data-turbo-confirm"]).to eq(malicious)
      # The raw HTML must NOT contain an unescaped <script> tag inside the attribute
      expect(render.to_html).not_to include('<script>alert("xss")</script>')
    end
  end
end
