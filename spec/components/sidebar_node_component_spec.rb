# frozen_string_literal: true

require "rails_helper"

RSpec.describe SidebarNodeComponent, type: :component do
  let(:node) { SidebarNode.new(key: "k", label: "Foo", menu_item: :pages, path: "/foo") }

  it "renders an anchor when path is present" do
    rendered = render_inline(described_class.new(node: node, current_path: "/"))
    expect(rendered.css("a").text).to include("Foo")
    expect(rendered.css("a").attr("href").value).to eq("/foo")
  end

  it "applies active indicator when current_path matches" do
    rendered = render_inline(described_class.new(node: node, current_path: "/foo"))
    expect(rendered.css(".bg-accent-subtle")).not_to be_empty
    expect(rendered.css('[aria-current="page"]')).not_to be_empty
  end

  it "renders children as nested list" do
    parent = SidebarNode.new(
      key: "p", label: "Parent", menu_item: :pages,
      children: [SidebarNode.new(key: "c", label: "Child", menu_item: :pages, path: "/c")]
    )
    rendered = render_inline(described_class.new(node: parent, current_path: "/"))
    expect(rendered.css("li li").text).to include("Child")
  end

  describe "match_prefix active state" do
    def prefix_node(path:, match_prefix: nil)
      SidebarNode.new(key: "k", label: "Billing", menu_item: :maintenance, path: path, match_prefix: match_prefix)
    end

    it "is active on the exact path" do
      c = described_class.new(node: prefix_node(path: "/1/admin/maintenance/platform/billing/plans"),
                              current_path: "/1/admin/maintenance/platform/billing/plans")
      expect(c.active?).to be(true)
    end

    it "is active on a sibling billing tab when match_prefix is set" do
      n = prefix_node(path: "/1/admin/maintenance/platform/billing/plans",
                      match_prefix: "/1/admin/maintenance/platform/billing")
      c = described_class.new(node: n, current_path: "/1/admin/maintenance/platform/billing/coupons")
      expect(c.active?).to be(true)
    end

    it "does not over-activate a non-matching path" do
      n = prefix_node(path: "/1/admin/maintenance/platform/billing/plans",
                      match_prefix: "/1/admin/maintenance/platform/billing")
      c = described_class.new(node: n, current_path: "/1/admin/maintenance/platform/module_settings")
      expect(c.active?).to be(false)
    end

    it "is active when current_path matches any prefix in an Array match_prefix" do
      n = prefix_node(path: "/1/admin/modules/emails/send_activities",
                      match_prefix: ["/1/admin/modules/emails/send_activities", "/1/admin/modules/emails/automations"])
      c = described_class.new(node: n, current_path: "/1/admin/modules/emails/automations")
      expect(c.active?).to be(true)
    end

    it "does not over-activate for a path outside an Array match_prefix" do
      n = prefix_node(path: "/1/admin/modules/emails/send_activities",
                      match_prefix: ["/1/admin/modules/emails/send_activities", "/1/admin/modules/emails/automations"])
      c = described_class.new(node: n, current_path: "/1/admin/modules/emails/templates")
      expect(c.active?).to be(false)
    end
  end

  it "exposes descendant labels on a filterable item" do
    parent = SidebarNode.new(
      key: "p", label: "Auth", menu_item: :settings, description: "Roles",
      children: [SidebarNode.new(key: "c", label: "Sign up", menu_item: :settings, path: "/c")]
    )
    rendered = render_inline(described_class.new(node: parent, current_path: "/", filterable: true))
    li = rendered.css("li").first
    expect(li["data-list-filter-target"]).to eq("item")
    expect(li["data-search-text"]).to include("Auth").and include("Roles").and include("Sign up")
  end

  describe "exact path aliases" do
    let(:account_security) do
      SidebarNode.new(key: "settings.modules.authentication", label: "Account security", menu_item: :settings,
        path: "/1/admin/settings/modules/authentication",
        match_paths: ["/1/admin/settings/modules/authentication", "/1/admin/settings/modules/authentications"])
    end

    it "selects either root with a query string or trailing slash" do
      account_security.match_paths.product(["", "/", "?locale=zh-CN", "/?return_to=/roles"]).each do |root, suffix|
        rendered = render_inline(described_class.new(node: account_security, current_path: "#{root}#{suffix}"))
        expect(rendered.css("a[aria-current='page']").length).to eq(1)
        expect(rendered.at_css("a")["href"]).to eq(account_security.path)
      end
    end

    it "never treats either root's children or another tenant's root as exact aliases" do
      paths = account_security.match_paths.product(["/sign_up", "/forget_password/", "/roles/12/grants?locale=en"]).map(&:join)
      paths << "/2/admin/settings/modules/authentications"
      paths.each do |path|
        expect(described_class.new(node: account_security, current_path: path).active?).to be(false), path
      end
    end

    it "preserves existing exact-path semantics for nodes without aliases" do
      expect(described_class.new(node: node, current_path: "/foo/").active?).to be(false)
      expect(described_class.new(node: node, current_path: "/foo?locale=en").active?).to be(false)
    end
  end

  it "uses wrapping labels with compact desktop rows and touch-sized mobile rows in settings" do
    settings = SidebarNode.new(key: "settings.email.template_tokens", label: "Email personalization", menu_item: :settings, path: "/tokens")
    rendered = render_inline(described_class.new(node: settings, current_path: "/", filterable: true))
    expect(rendered.css("a").first["class"]).to include("min-h-9", "text-body-sm")
    expect(rendered.css("a").first["class"]).not_to include("min-h-11")
    expect(rendered.css("a span").first["class"]).not_to include("truncate")
    expect(rendered.css("li").first["data-search-text"]).to include("template tokens")

    mobile = render_inline(described_class.new(node: settings, current_path: "/", mobile: true))
    expect(mobile.css("a").first["class"]).to include("min-h-11")
  end

  describe "Modules and Settings styling" do
    let(:group) do
      SidebarNode.new(key: "modules.email", label: "Email", menu_item: :modules, icon: "M3 3", tone: "email", children: [
        SidebarNode.new(key: "modules.email.howto", label: "How to use", menu_item: :modules, path: "/m/howto", icon: "M4 4"),
        SidebarNode.new(key: "modules.email.lists", label: "Lists", menu_item: :modules, children: [
          SidebarNode.new(key: "modules.email.lists.all", label: "All lists", menu_item: :modules, path: "/m/lists")
        ])
      ])
    end

    it "tints the top-level icon tile by module and drops icons from sub-items" do
      rendered = render_inline(described_class.new(node: group, current_path: "/"))
      tile = rendered.at_css("summary > span[aria-hidden='true']")
      expect(tile["class"]).to include("size-6", "bg-info-subtle", "text-info")
      expect(rendered.css("details ul a svg")).to be_empty
    end

    it "shows no count of nested destinations beside the chevron of a collapsed group" do
      rendered = render_inline(described_class.new(node: group, current_path: "/"))
      expect(rendered.at_css("details")["open"]).to be_nil
      expect(rendered.at_css("summary").text.squish).to eq("Email")
      expect(rendered).not_to have_css("summary span.tabular-nums")
    end

    it "opens the group holding the selected child, marks it on the guide line and emphasizes the parent" do
      rendered = render_inline(described_class.new(node: group, current_path: "/m/howto", selected_key: "modules.email.howto"))
      expect(rendered.at_css("details")["open"]).not_to be_nil
      expect(rendered.at_css("summary")["class"]).to include("font-medium", "text-text-primary")
      expect(rendered.at_css("details > ul")["class"]).to include("border-l", "ml-[19px]")
      expect(rendered.at_css("a[aria-current='page']")["class"]).to include("min-h-8", "before:bg-accent")
    end

    it "keeps groups closed when the selection lies elsewhere" do
      rendered = render_inline(described_class.new(node: group, current_path: "/m/howto", selected_key: "modules.other"))
      expect(rendered.at_css("details")["open"]).to be_nil
      none = render_inline(described_class.new(node: group, current_path: "/m/howto", selected_key: nil))
      expect(none.at_css("details")["open"]).to be_nil
    end

    it "gives untoned tiles a neutral well that turns accent when the row is active" do
      overview = SidebarNode.new(key: "modules.overview", label: "Overview", menu_item: :modules, path: "/m", icon: "M1 1")
      idle = render_inline(described_class.new(node: overview, current_path: "/x"))
      expect(idle.at_css("a > span[aria-hidden='true']")["class"]).to include("bg-surface-active")
      active = render_inline(described_class.new(node: overview, current_path: "/m"))
      expect(active.at_css("a > span[aria-hidden='true']")["class"]).to include("text-accent", "ring-accent/20")
    end

    it "leaves other menus on their glyph icons and indented rows" do
      maintenance = SidebarNode.new(key: "maintenance.entities", label: "All", menu_item: :maintenance, path: "/p", icon: "M1 1")
      rendered = render_inline(described_class.new(node: maintenance, current_path: "/", depth: 1))
      expect(rendered.at_css("a > svg")["class"]).to include("size-[18px]")
      expect(rendered.at_css("a")["class"]).to include("pl-8")
    end
  end

  describe "Pages and Entities styling" do
    let(:long_name) { "PwCampaign1788416325268 with a very long name" }

    it "uses the soft icon tile and truncates long record names with the full name as a tooltip" do
      node = SidebarNode.new(key: "entities.pwc", label: long_name, menu_item: :entities, path: "/e/1", icon: "M1 1")
      rendered = render_inline(described_class.new(node: node, current_path: "/x"))
      link = rendered.at_css("a")
      expect(link["class"]).to include("min-h-9", "rounded-md")
      expect(link["title"]).to eq(long_name)
      expect(rendered.at_css("a > span[aria-hidden='true']")["class"]).to include("size-6", "bg-surface-active")
      expect(rendered.at_css("a > span:not([aria-hidden])")["class"]).to include("truncate")
    end

    it "truncates a linked group summary and lists children on the guide line" do
      node = SidebarNode.new(key: "entities.student", label: long_name, menu_item: :entities, path: "/e/2", icon: "M1 1",
                             children: [SidebarNode.new(key: "entities.guardian", label: "Guardians", menu_item: :entities, path: "/e/3")])
      rendered = render_inline(described_class.new(node: node, current_path: "/e/3", selected_key: "entities.guardian"))
      expect(rendered.at_css("summary a")["title"]).to eq(long_name)
      expect(rendered.at_css("summary a")["class"]).to include("min-w-0", "truncate")
      expect(rendered.at_css("details > ul")["class"]).to include("border-l")
      expect(rendered.at_css("a[aria-current='page']")["class"]).to include("before:bg-accent")
    end

    it "renders numeric badges as a quiet trailing count that dims at zero and turns accent when active" do
      node = ->(count) { SidebarNode.new(key: "pages.e", label: "Students", menu_item: :pages, path: "/p/e", badge: { label: count }) }

      idle = render_inline(described_class.new(node: node.call("4"), current_path: "/x"))
      expect(idle).not_to have_css(".badge")
      expect(idle.at_css("span.tabular-nums").text).to eq("4")
      expect(idle.at_css("span.tabular-nums")["class"]).to include("ml-auto", "text-text-muted")

      zero = render_inline(described_class.new(node: node.call("0"), current_path: "/x"))
      expect(zero.at_css("span.tabular-nums")["class"]).to include("text-text-muted/60")

      active = render_inline(described_class.new(node: node.call("4"), current_path: "/p/e"))
      expect(active.at_css("span.tabular-nums")["class"]).to include("text-accent")
    end

    it "keeps text badges as pills" do
      node = SidebarNode.new(key: "pages.e", label: "Students", menu_item: :pages, path: "/p/e", badge: { label: "Beta" })
      rendered = render_inline(described_class.new(node: node, current_path: "/x"))
      expect(rendered.at_css(".badge.badge-default").text.strip).to eq("Beta")
    end

    describe "Domains sidebar" do
      let(:entity) do
        SidebarNode.new(key: "entities.7", label: "Students", menu_item: :entities, path: "/e/7",
                        monogram: "S", tone: SidebarTone.entity("sky"))
      end
      let(:domain) do
        SidebarNode.new(key: "entities.domain.1", label: "Academics", menu_item: :entities, icon: "M1 1",
                        path: "/d/1", tone: SidebarTone.domain("blue"), children: [entity])
      end

      it "opens the selected domain, links its label and lifts its tinted tile onto a white chip" do
        rendered = render_inline(described_class.new(node: domain, current_path: "/d/1", selected_key: "entities.domain.1"))
        expect(rendered.at_css("details")["open"]).not_to be_nil
        expect(rendered.at_css("summary a[href='/d/1'][aria-current='page']").text).to eq("Academics")
        tile = rendered.at_css("summary > [data-role='tile']")["class"]
        expect(tile).to include("size-6", "bg-surface", "text-blue-700", "ring-blue-200")
        expect(tile).not_to include("bg-blue-50")
      end

      it "keeps an unselected domain collapsed, tinted with its colour" do
        rendered = render_inline(described_class.new(node: domain, current_path: "/x", selected_key: nil))
        expect(rendered.at_css("details")["open"]).to be_nil
        expect(rendered.at_css("summary > [data-role='tile']")["class"]).to include("size-6", "bg-blue-50", "text-blue-700", "ring-1")
      end

      it "gives toned sub-items a small tile with their monogram when they have no icon" do
        rendered = render_inline(described_class.new(node: domain, current_path: "/x"))
        tile = rendered.at_css("details ul a > [data-role='tile']")
        expect(tile["class"]).to include("size-5", "bg-surface-active", "text-sky-700")
        expect(tile.text.strip).to eq("S")
        expect(tile).not_to have_css("svg")
        expect(rendered.at_css("details ul a")["class"]).to include("px-2")
      end

      it "lifts the active sub-item tile onto a white chip" do
        rendered = render_inline(described_class.new(node: domain, current_path: "/e/7"))
        tile = rendered.at_css("a[aria-current='page'] > [data-role='tile']")
        expect(tile["class"]).to include("bg-surface", "shadow-xs", "ring-accent/20")
        expect(tile["class"]).not_to include("bg-surface-active")
      end
    end

    it "does not truncate or add tooltips to Settings and Modules labels" do
      node = SidebarNode.new(key: "modules.overview", label: "Overview", menu_item: :modules, path: "/m")
      rendered = render_inline(described_class.new(node: node, current_path: "/x"))
      expect(rendered.at_css("a")["title"]).to be_nil
      expect(rendered.at_css("a > span")["class"]).to include("break-words")
    end
  end
end
