# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminPageComponent, type: :component do
  let(:breadcrumbs) { [{ label: "Maintenance", path: "/123/admin/maintenance" }, { label: "Constants" }] }

  def render_page(**overrides, &block)
    args = {
      breadcrumbs: breadcrumbs,
      title:       "Constants",
      description: "Manage dropdown options",
      actions:     []
    }.merge(overrides)
    if block_given?
      render_inline(described_class.new(**args), &block)
    else
      render_inline(described_class.new(**args)) { "<p>body</p>".html_safe }
    end
  end

  it "renders the title" do
    expect(render_page.text).to include("Constants")
  end

  it "renders the description" do
    expect(render_page.text).to include("Manage dropdown options")
  end

  it "skips the description block when not provided" do
    rendered = render_page(description: nil)
    expect(rendered.css("p.text-body-sm")).to be_empty
  end

  it "renders breadcrumbs when provided" do
    rendered = render_page
    expect(rendered.text).to include("Maintenance")
    expect(rendered.text).to include("Constants")
  end

  context "when no title and no actions are given (breadcrumb-only header)" do
    it "omits the title strip entirely but still renders breadcrumbs and body" do
      rendered = render_inline(
        described_class.new(breadcrumbs: breadcrumbs)
      ) { "<div data-marker=\"body\">hi</div>".html_safe }

      expect(rendered.css("h1")).to be_empty
      expect(rendered.text).to include("Maintenance")
      expect(rendered.css("[data-marker='body']")).not_to be_empty
    end
  end

  it "renders the body block" do
    rendered = render_page { "<div data-marker=\"body\">hello</div>".html_safe }
    expect(rendered.css("[data-marker='body']")).not_to be_empty
  end

  describe "actions" do
    it "renders nothing when actions is empty" do
      expect(render_page.css("a.btn")).to be_empty
    end

    it "renders one button per action with the correct href and label" do
      rendered = render_page(actions: [
        { label: "New Constant", path: "/new", variant: :primary, icon: :plus },
        { label: "Trash",        path: "/trash", variant: :ghost, icon: :trash }
      ])
      expect(rendered.css("a[href='/new']").text).to include("New Constant")
      expect(rendered.css("a[href='/trash']").text).to include("Trash")
    end

    it "applies the requested variant class" do
      rendered = render_page(actions: [{ label: "Go", path: "/go", variant: :primary }])
      expect(rendered.css("a.btn-primary")).not_to be_empty
    end

    it "renders an inline icon SVG when an icon key is provided" do
      rendered = render_page(actions: [{ label: "Add", path: "/add", icon: :plus }])
      expect(rendered.css("a svg path[d='M12 4v16m8-8H4']")).not_to be_empty
    end

    it "passes target and rel through on link actions" do
      rendered = render_page(actions: [{
        label: "Preview", path: "/preview", target: "_blank", rel: "noopener noreferrer"
      }])
      anchor = rendered.css("a[href='/preview']").first
      expect(anchor["target"]).to eq("_blank")
      expect(anchor["rel"]).to eq("noopener noreferrer")
    end

    it "wraps a long title instead of truncating it" do
      rendered = render_page(title: "A very long customer name", wrap_title: true)
      heading = rendered.css("h1").first
      expect(heading["class"]).to include("whitespace-normal", "break-words")
      expect(heading["class"]).not_to include("truncate")
    end

    it "renders an action with :method as a button inside its own form" do
      rendered = render_page(actions: [
        { label: "Delete", path: "/customers/1", method: :delete, variant: :danger, data: { turbo_confirm: "Delete this customer?" } }
      ])

      form = rendered.css("form[action='/customers/1']").first
      expect(form).not_to be_nil
      expect(form.css("input[name='_method']").first["value"]).to eq("delete")
      button = form.css("button").first
      expect(button.text).to include("Delete")
      expect(button["class"]).to include("btn-danger")
      expect(button["data-turbo-confirm"]).to eq("Delete this customer?")
    end

    it "renders an action with :form as a submit button bound to that form id" do
      rendered = render_page(actions: [
        { label: "Save", form: "email_template_form", variant: :primary }
      ])

      button = rendered.css("button[type='submit'][form='email_template_form']").first
      expect(button).not_to be_nil
      expect(button.text).to include("Save")
      expect(button["class"]).to include("btn-primary")
      expect(rendered.css("a.btn")).to be_empty
    end

    it "opts into stacked mobile actions, wrapping tablet actions and a wrapping desktop header" do
      rendered = render_page(wrap_actions: true, actions: [
        { label: "Create Entry", path: "/new", class: "min-h-11 w-full sm:w-auto", data: { turbo_frame: "_top" } },
        { label: "Export CSV", path: "/export", class: "min-h-11 w-full sm:w-auto" }
      ])
      action = rendered.at_css("a[href='/new']")
      expect(action["data-turbo-frame"]).to eq("_top")
      expect(action.parent["class"]).to include("w-full", "flex-col", "sm:flex-row", "sm:flex-wrap", "lg:w-auto")
      expect(action.parent["class"]).not_to include("sm:flex-nowrap")
      expect(action.parent.parent["class"]).to include("lg:flex-row", "lg:flex-wrap")
    end
  end

  # Flash alerts are now rendered solely by the dashboard layout, never by this
  # component, so the page shell never emits an alert region itself.
  it "does not render a flash alert region" do
    rendered = render_page
    expect(rendered.css(".bg-success-subtle, .bg-danger-subtle")).to be_empty
  end

  describe "badges" do
    it "renders badges after the title" do
      rendered = render_page(badges: [
        { label: "Active", variant: :success },
        { label: "Configured", variant: :default, data: { module_settings_health: "success" } }
      ])

      expect(rendered.css("h1").text).to include("Constants")
      expect(rendered.text).to include("Active")
      expect(rendered.css("[data-module-settings-health='success']").text).to include("Configured")
    end

    it "renders no badges when the list is empty" do
      rendered = render_page(badges: [])
      expect(rendered.css("[data-module-settings-health]")).to be_empty
    end
  end

  describe "identity icon" do
    it "renders a tinted icon tile when icon_path is given" do
      rendered = render_page(
        icon_path: "M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z",
        icon_class: "bg-info-subtle text-info"
      )

      expect(rendered.css("span.bg-info-subtle svg path[d='M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z']")).not_to be_empty
    end

    it "omits the identity tile when icon_path is blank" do
      rendered = render_page(icon_path: nil)
      expect(rendered.css("span.size-10")).to be_empty
    end
  end

  it "fills the remaining viewport when width is :edge" do
    rendered = render_page(width: :edge)

    expect(rendered.css("[data-admin-page-workspace]")).not_to be_empty
    expect(rendered.css("h1").text).to include("Constants")
  end

  describe "document title" do
    it "sets the browser title from the page heading" do
      context = vc_test_view_context
      context.render(described_class.new(breadcrumbs: breadcrumbs, title: "Constants")) { "" }

      expect(context.content_for(:title)).to eq("Constants")
    end

    it "strips markup from the heading" do
      context = vc_test_view_context
      context.render(described_class.new(breadcrumbs: breadcrumbs, title: "Course <em>101</em>")) { "" }

      expect(context.content_for(:title)).to eq("Course 101")
    end

    it "leaves an existing document title in place" do
      context = vc_test_view_context
      context.content_for(:title, "AI Assistant")
      context.render(described_class.new(breadcrumbs: breadcrumbs, title: "Constants")) { "" }

      expect(context.content_for(:title)).to eq("AI Assistant")
    end

    it "does not set a document title when the page has no heading" do
      context = vc_test_view_context
      context.render(described_class.new(breadcrumbs: breadcrumbs)) { "" }

      expect(context.content_for?(:title)).to be false
    end
  end
end
