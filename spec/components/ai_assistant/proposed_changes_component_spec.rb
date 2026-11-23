# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::ProposedChangesComponent, type: :component do
  # The payload contract the server parks on the assistant message: machine
  # values only, so every word on screen is this component's to translate.
  def proposal(rows, kind: "operation", name: "Contact", plan: nil)
    {
      "kind" => kind,
      "operation" => "update_entity",
      "invocation_id" => 123,
      "customer_id" => 81_721_200,
      "plan" => plan || [ { "name" => name, "id" => 12, "breaking" => false, "rows" => rows } ]
    }
  end

  def render_rows(rows, **options)
    render_inline(described_class.new(proposal: proposal(rows, **options)))
  end

  def t(key, **arguments)
    I18n.t("ai_assistant.assistant.plan.#{key}", **arguments)
  end

  def row_text(key, **arguments)
    t("rows.#{key}", **arguments)
  end

  def field(name)
    t("fields.#{name}")
  end

  describe "whether there is anything to show" do
    it "renders nothing without a proposal" do
      render_inline(described_class.new(proposal: nil))

      expect(page).not_to have_css("[data-proposal]")
    end

    it "renders nothing for a payload that is not a hash" do
      render_inline(described_class.new(proposal: "nope"))

      expect(page).not_to have_css("[data-proposal]")
    end

    # A flowchart proposal has no change plan, so there is nothing to lay out.
    it "renders nothing for a proposal that is not an operation update" do
      render_rows(
        [ { "kind" => "identity", "action" => "modified", "field" => "display_label", "after" => "Contacts" } ],
        kind: "flowchart"
      )

      expect(page).not_to have_css("[data-proposal]")
    end

    # The document protocol is gone; leftover `entity` payloads must not render
    # as if they were still the confirmation gate.
    it "renders nothing for a leftover entity-kind proposal" do
      render_rows(
        [ { "kind" => "attribute", "action" => "added", "name" => "Phone", "breaking" => false } ],
        kind: "entity"
      )

      expect(page).not_to have_css("[data-proposal]")
    end

    it "renders an operation-kind proposal's plan" do
      render_rows(
        [ { "kind" => "attribute", "action" => "added", "name" => "Phone", "html_type" => "tel", "breaking" => false } ],
        kind: "operation"
      )

      expect(page).to have_css("[data-proposal='pending']")
      expect(page).to have_text(row_text("attribute_added", name: "Phone"))
    end

    it "renders nothing when the plan is absent, blank, or the wrong shape" do
      [ nil, [], "plan", {} ].each do |value|
        render_inline(described_class.new(proposal: { "kind" => "operation", "plan" => value }))

        expect(page).not_to have_css("[data-proposal]")
      end
    end

    it "renders nothing when no plan entry is even a hash" do
      render_rows([], plan: [ "not a hash", nil, 7 ])

      expect(page).not_to have_css("[data-proposal]")
    end

    # The inverse of the above: an entry that IS a hash is gating the write, so
    # it gets a card whatever shape its rows are in.
    it "still cards an entry whose rows are missing or the wrong shape" do
      [ [], "nope", nil ].each do |rows|
        render_rows([], plan: [ { "name" => "Contact", "rows" => rows } ])

        expect(page).to have_css("[data-proposal='pending']")
        expect(page).to have_text(row_text("unplannable"))
      end
    end
  end

  describe "the rows the backend emits" do
    it "renames an identity field, showing both sides" do
      render_rows(
        [
          {
            "kind" => "identity", "action" => "modified", "field" => "display_label",
            "before" => "Contact", "after" => "Contacts", "breaking" => false
          }
        ]
      )

      expect(page).to have_css("[data-proposal='pending']")
      expect(page).to have_text("Contact")
      expect(page).to have_text(row_text("identity_modified", field: field("display_label")))
      expect(page).to have_css("code", text: "Contact")
      expect(page).to have_css("code", text: "Contacts")
    end

    it "adds a field and names the type it will use" do
      render_rows(
        [ { "kind" => "attribute", "action" => "added", "name" => "Phone", "html_type" => "tel", "breaking" => false } ]
      )

      expect(page).to have_text(row_text("attribute_added", name: "Phone"))
      expect(page).to have_css("code", text: HtmlTypeOptions.label_for("tel"))
    end

    it "adds a field whose type the proposal left out" do
      render_rows([ { "kind" => "attribute", "action" => "added", "name" => "Phone", "breaking" => false } ])

      expect(page).to have_text(row_text("attribute_added", name: "Phone"))
      expect(page).not_to have_css("code")
    end

    it "removes a field as a breaking row, in both locales" do
      row = { "kind" => "attribute_removed", "action" => "removed", "name" => "Fax", "breaking" => true }

      %i[en zh-CN].each do |locale|
        I18n.with_locale(locale) do
          render_rows([ row ])

          expect(page).to have_text(row_text("attribute_removed", name: "Fax"))
          expect(page).to have_text(t("breaking_badge"))
          expect(page).to have_css("li.bg-warning-subtle.text-warning", count: 1)
        end
      end

      english = I18n.with_locale(:en) { render_rows([ row ]) && page.find("li").text }
      chinese = I18n.with_locale(:"zh-CN") { render_rows([ row ]) && page.find("li").text }
      expect(english).not_to eq(chinese)
    end

    it "changes a field's type, humanising both sides" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Email", "field" => "html_type",
            "before" => "text", "after" => "email", "breaking" => true
          }
        ]
      )

      expect(page).to have_text(row_text("attribute_modified", name: "Email", field: field("html_type")))
      expect(page).to have_css("code", text: HtmlTypeOptions.label_for("text"))
      expect(page).to have_css("code", text: HtmlTypeOptions.label_for("email"))
      # The registry key itself is an implementation detail of the field editor.
      expect(page).not_to have_css("code", text: "text", exact_text: true)
    end

    # A vendor key the registry has never heard of still has to render as
    # something, and the raw value is the only honest option.
    it "falls back to the raw type when the registry has no label for it" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Email", "field" => "html_type",
            "before" => "text_input", "after" => "email_input", "breaking" => true
          }
        ]
      )

      expect(page).to have_css("code", text: "text_input")
      expect(page).to have_css("code", text: "email_input")
    end

    it "changes a field's validators" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Email", "field" => "validators",
            "before" => "presence", "after" => "format, presence", "breaking" => false
          }
        ]
      )

      expect(page).to have_text(row_text("attribute_modified", name: "Email", field: field("validators")))
      expect(page).to have_css("code", text: "presence")
      expect(page).to have_css("code", text: "format, presence")
    end

    it "lists added and removed options as separate lines" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Tier", "field" => "options",
            "added" => [ "Bronze", "Silver" ], "removed" => [ "Tin" ], "breaking" => false
          }
        ]
      )

      expect(page).to have_text(row_text("attribute_options_added", name: "Tier"))
      expect(page).to have_text(row_text("attribute_options_removed", name: "Tier"))
      expect(page).to have_css("code", text: "Bronze")
      expect(page).to have_css("code", text: "Silver")
      expect(page).to have_css("code", text: "Tin")
    end

    # Relabelling an option in place (same value, new label) used to slip
    # through with no row at all, so it applied without confirmation.
    it "renames an option in place, showing both labels" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Tier", "field" => "options",
            "added" => [], "removed" => [],
            "relabelled" => [ { "before" => "Applied", "after" => "Renamed label" } ],
            "breaking" => false
          }
        ]
      )

      expect(page).to have_text(row_text("attribute_options_relabelled", name: "Tier"))
      expect(page).not_to have_text(row_text("attribute_options_added", name: "Tier"))
      expect(page).not_to have_text(row_text("attribute_options_removed", name: "Tier"))
      expect(page).to have_css("code.line-through", text: "Applied")
      expect(page).to have_css("code", text: "Renamed label")
    end

    it "splits a change that adds, drops, and renames options into three lines" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Tier", "field" => "options",
            "added" => [ "Platinum" ], "removed" => [ "Tin" ],
            "relabelled" => [
              { "before" => "Bronze", "after" => "Standard" },
              { "before" => "Silver", "after" => "Plus" }
            ],
            "breaking" => false
          }
        ]
      )

      expect(page).to have_css("li", count: 3)
      expect(page).to have_text(row_text("attribute_options_added", name: "Tier"))
      expect(page).to have_text(row_text("attribute_options_removed", name: "Tier"))
      expect(page).to have_text(row_text("attribute_options_relabelled", name: "Tier"))
      expect(page).to have_css("code", text: "Platinum")
      expect(page).to have_css("code", text: "Tin")
      expect(page).to have_css("code.line-through", text: "Bronze")
      expect(page).to have_css("code", text: "Standard")
      expect(page).to have_css("code.line-through", text: "Silver")
      expect(page).to have_css("code", text: "Plus")
      # Two renames, each an old label struck through beside its new one.
      expect(page).to have_css("code.line-through", count: 2)
    end

    it "drops a relabel entry that is malformed or missing a side" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Tier", "field" => "options",
            "added" => [], "removed" => [],
            "relabelled" => [
              "not a hash",
              nil,
              { "before" => "Bronze" },
              { "after" => "Plus" },
              { "before" => "  ", "after" => "Plus" },
              { "before" => "Silver", "after" => "" },
              { "before" => "Gold", "after" => "Premium" }
            ],
            "breaking" => false
          }
        ]
      )

      expect(page).to have_text(row_text("attribute_options_relabelled", name: "Tier"))
      expect(page).to have_css("code", text: "Gold")
      expect(page).to have_css("code", text: "Premium")
      expect(page).to have_css("code", count: 2)
      expect(rendered_content).not_to include("translation missing")
    end

    # An options row with nothing usable in any bucket still gated the write,
    # so it says the list changed without pretending to know how.
    it "names an options change it cannot itemise" do
      [
        { "added" => [], "removed" => [], "relabelled" => { "before" => "Gold" } },
        { "added" => [], "removed" => [], "relabelled" => [] }
      ].each do |buckets|
        render_rows(
          [
            {
              "kind" => "attribute", "action" => "modified", "name" => "Tier", "field" => "options",
              "breaking" => false
            }.merge(buckets)
          ]
        )

        expect(page).to have_text(row_text("attribute_modified", name: "Tier", field: field("options")))
        expect(page).to have_css("li", count: 1)
        expect(page).not_to have_css("code")
      end
    end

    it "ignores option entries that carry no value, and lists that are not lists" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Tier", "field" => "options",
            "added" => [ "Bronze", "", "  ", nil ], "removed" => "Tin", "breaking" => false
          }
        ]
      )

      expect(page).to have_css("code", text: "Bronze")
      expect(page).to have_css("code", count: 1)
      expect(page).not_to have_text(row_text("attribute_options_removed", name: "Tier"))
    end

    it "renames a field without moving its slug" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Email", "field" => "name",
            "before" => "Email", "after" => "Email address", "breaking" => false
          }
        ]
      )

      expect(page).to have_text(row_text("attribute_modified", name: "Email", field: field("name")))
      expect(page).to have_css("code", text: "Email address")
    end

    it "names the setting inside a config change rather than the blob" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Amount", "field" => "config",
            "config_key" => "precision", "before" => 2, "after" => 4, "breaking" => false
          }
        ]
      )

      expect(page).to have_text(
        row_text("attribute_modified", name: "Amount", field: t("config_fields.precision"))
      )
      expect(page).to have_css("code", text: "2")
      expect(page).to have_css("code", text: "4")
      expect(page).not_to have_text(field("config"))
    end

    it "names the editor config keys the plan can now emit" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Status", "field" => "config",
            "config_key" => "source", "before" => "manual", "after" => "constant", "breaking" => false
          },
          {
            "kind" => "attribute", "action" => "modified", "name" => "Resume", "field" => "config",
            "config_key" => "multiple", "before" => false, "after" => true, "breaking" => false
          }
        ]
      )

      expect(page).to have_text(
        row_text("attribute_modified", name: "Status", field: t("config_fields.source"))
      )
      expect(page).to have_text(
        row_text("attribute_modified", name: "Resume", field: t("config_fields.multiple"))
      )
      expect(page).to have_css("code", text: t("boolean.false"))
      expect(page).to have_css("code", text: t("boolean.true"))
      expect(rendered_content).not_to include(">false<")
      expect(rendered_content).not_to include(">true<")
    end

    it "falls back to the blob's own name when a config row names no setting" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Amount", "field" => "config",
            "config_key" => "  ", "before" => 2, "after" => 4, "breaking" => false
          }
        ]
      )

      expect(page).to have_text(row_text("attribute_modified", name: "Amount", field: field("config")))
    end

    it "describes groups, associations, and the default properties" do
      render_rows(
        [
          { "kind" => "group", "action" => "added", "name" => "Contact details", "breaking" => false },
          { "kind" => "group", "action" => "modified", "name" => "Billing", "breaking" => false },
          { "kind" => "group", "action" => "removed", "name" => "Legacy", "breaking" => false },
          { "kind" => "association", "action" => "added", "name" => "Company", "breaking" => false },
          { "kind" => "association", "action" => "modified", "name" => "Owner", "breaking" => false },
          { "kind" => "association", "action" => "removed", "name" => "Vendor", "breaking" => false },
          { "kind" => "default_properties", "action" => "modified", "breaking" => false }
        ]
      )

      expect(page).to have_text(row_text("group_added", name: "Contact details"))
      expect(page).to have_text(row_text("group_modified", name: "Billing"))
      expect(page).to have_text(row_text("group_removed", name: "Legacy"))
      expect(page).to have_text(row_text("association_added", name: "Company"))
      expect(page).to have_text(row_text("association_modified", name: "Owner"))
      expect(page).to have_text(row_text("association_removed", name: "Vendor"))
      expect(page).to have_text(row_text("default_properties_modified"))
      expect(page).to have_css("li", count: 7)
    end

    it "names a value the proposal leaves empty rather than showing a gap" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Notes", "field" => "description",
            "before" => "", "after" => "Freeform notes", "breaking" => false
          }
        ]
      )

      expect(page).to have_css("code", text: t("none"))
      expect(page).to have_css("code", text: "Freeform notes")
    end

    # `false` is a value a readonly row really takes, so it must not be
    # misreported as an absence — nor shown to the admin as the word "false".
    it "treats false as a value, not as nothing" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Notes", "field" => "readonly",
            "before" => true, "after" => false, "breaking" => false
          }
        ]
      )

      expect(page).to have_css("code", text: t("boolean.true"))
      expect(page).to have_css("code", text: t("boolean.false"))
      expect(page).not_to have_css("code", text: t("none"))
      expect(rendered_content).not_to include(">false<")
    end

    it "lists every entity a single proposal touches" do
      render_rows(
        [],
        plan: [
          {
            "name" => "Contact", "id" => 12, "breaking" => false,
            "rows" => [ { "kind" => "attribute", "action" => "added", "name" => "Phone", "breaking" => false } ]
          },
          {
            "name" => "Company", "id" => 13, "breaking" => false,
            "rows" => [ { "kind" => "association", "action" => "added", "name" => "Contact", "breaking" => false } ]
          }
        ]
      )

      expect(page).to have_text("Contact")
      expect(page).to have_text("Company")
      expect(page).to have_css("li", count: 2)
    end
  end

  # The server sends raw machine values — hashes, arrays, booleans, enum keys —
  # and every one of them is worded here. Rendering any of them with `to_s` is
  # what put a literal Ruby hash in front of the admin, identically in both
  # locales, which is the finding these examples hold closed.
  describe "the raw value shapes" do
    def attribute_row(field, before:, after:)
      [
        {
          "kind" => "attribute", "action" => "modified", "name" => "Email", "field" => field,
          "before" => before, "after" => after, "breaking" => false
        }
      ]
    end

    def audience(key) = I18n.t("comp_admin.attribute_modal.#{key}")

    %w[visibility validator_apply].each do |field|
      it "reduces a #{field} map to the audiences it enables" do
        render_rows(
          attribute_row(
            field,
            before: { "admin" => true, "member" => true, "public" => true },
            after: { "admin" => true, "member" => false, "public" => false }
          )
        )

        expect(page).to have_css("code", text: [ audience("admin"), audience("member"), audience("public") ]
          .join(t("list_separator")))
        expect(page).to have_css("code", text: audience("admin"), exact_text: true)
        expect(rendered_content).not_to include("=&gt;")
      end
    end

    # The audience map defaults the way EntityAttributeAudience reads it: only
    # an explicit false takes an audience away.
    it "counts an audience the map does not mention as enabled" do
      render_rows(attribute_row("visibility", before: { "member" => false }, after: {}))

      expect(page).to have_css("code", text: [ audience("admin"), audience("public") ].join(t("list_separator")))
      expect(page).to have_css(
        "code",
        text: [ audience("admin"), audience("member"), audience("public") ].join(t("list_separator"))
      )
    end

    it "says so when a map enables nobody" do
      render_rows(
        attribute_row("visibility", before: nil, after: { "admin" => false, "member" => false, "public" => false })
      )

      expect(page).to have_css("code", text: t("audiences_none"))
      expect(page).to have_css("code", text: t("none"))
    end

    it "translates the audiences rather than repeating the payload" do
      I18n.with_locale(:"zh-CN") do
        render_rows(attribute_row("visibility", before: nil, after: { "admin" => true, "member" => false }))
      end

      expect(page).to have_css("code", text: I18n.t("comp_admin.attribute_modal.admin", locale: :"zh-CN"))
      expect(rendered_content).not_to include("admin")
    end

    it "words each validator through the registry the field editor uses" do
      render_rows(attribute_row("validators", before: [ "presence" ], after: %w[format_email presence]))

      expect(page).to have_css("code", text: ValidatorRegistry.validator_label("presence"), exact_text: true)
      expect(page).to have_css(
        "code",
        text: [ "format_email", "presence" ].map { |key| ValidatorRegistry.validator_label(key) }
                                            .join(t("list_separator"))
      )
      expect(rendered_content).not_to include("format_email")
    end

    it "treats an emptied validator list as nothing set" do
      render_rows(attribute_row("validators", before: [ "presence" ], after: []))

      expect(page).to have_css("code", text: t("none"))
    end

    it "words a static options source instead of showing the word static" do
      render_rows(attribute_row("options_source", before: nil, after: { "kind" => "static" }))

      expect(page).to have_css("code", text: t("options_source.static"))
      expect(rendered_content).not_to include("static")
    end

    it "words an entity-bound options source, with and without a value field" do
      render_rows(
        attribute_row(
          "options_source",
          before: { "kind" => "entity", "entity_name" => "Product" },
          after: { "kind" => "entity", "entity_name" => "Product" }
        )
      )

      expect(page).to have_css("code", text: t("options_source.entity", entity: "Product"), exact_text: true)
      expect(page).to have_css("code", text: t("options_source.entity", entity: "Product"))
    end

    it "keeps an unusable options source readable without leaking its shape" do
      render_rows(
        attribute_row(
          "options_source",
          before: { "kind" => "catalog" },
          after: { "kind" => "entity", "entity_name" => "  " }
        )
      )

      expect(page).to have_css("code", text: t("options_source.other", kind: "catalog"))
      expect(page).to have_css("code", text: t("options_source.other", kind: "entity"))
    end

    it "words the enum keys behind type and storage" do
      render_rows(
        attribute_row("type", before: nil, after: "Computed") +
          [
            {
              "kind" => "attribute", "action" => "modified", "name" => "Email", "field" => "storage",
              "before" => "stored", "after" => "computed", "breaking" => false
            }
          ]
      )

      expect(page).to have_css("code", text: t("values.type.Computed"))
      expect(page).to have_css("code", text: t("values.storage.stored"))
      expect(page).to have_css("code", text: t("values.storage.computed"))
    end

    # An enum value added upstream must read as itself, not as a missing key.
    it "falls back to the enum value when it has no label yet" do
      render_rows(attribute_row("type", before: "Computed", after: "Rollup"))

      expect(page).to have_css("code", text: "Rollup")
      expect(rendered_content).not_to include("translation missing")
    end

    it "shows a resolved section name as plain text" do
      render_rows(attribute_row("group_id", before: nil, after: "Contact details"))

      expect(page).to have_text(row_text("attribute_modified", name: "Email", field: field("group_id")))
      expect(page).to have_css("code", text: "Contact details")
    end

    # The hard-rule finding, narrowed to the config shape: `attributeConfig`
    # declares `filter` as an object, `Normalizer` keeps it intact, and
    # ChangePlan emits a row for it. Rendering it with `to_s` put Ruby
    # `inspect` syntax — `{"slug"=>"score", ...}` — in front of the admin,
    # byte-identical under zh-CN. Every key is worded and every value is its
    # own, in whichever locale is asking.
    it "words an object-valued config row instead of showing a Ruby hash (I18n hard rule)" do
      filter_row = [
        {
          "kind" => "attribute", "action" => "modified", "name" => "Score Total", "field" => "config",
          "config_key" => "filter",
          "before" => { "slug" => "score", "op" => ">", "value" => 3 },
          "after" => { "slug" => "score", "op" => ">=", "value" => 5 },
          "breaking" => false
        }
      ]

      %i[en zh-CN].each do |locale|
        I18n.with_locale(locale) do
          render_rows(filter_row)

          expect(page).to have_text(
            row_text("attribute_modified", name: "Score Total", field: t("config_fields.filter"))
          )
          [ %w[score >], %w[score >=] ].each_with_index do |(slug, op), index|
            expect(page).to have_css(
              "code",
              text: [
                t("pair", label: t("config_fields.slug"), value: slug),
                t("pair", label: t("config_fields.op"), value: op),
                t("pair", label: t("config_fields.value"), value: index.zero? ? "3" : "5")
              ].join(t("list_separator")),
              exact_text: true
            )
          end
          # The shape that was leaking: Ruby's hash rocket and its quoted keys.
          expect(rendered_content).not_to include("=&gt;")
          expect(rendered_content).not_to include("&quot;slug&quot;")
        end
      end

      # And the two locales really do read differently, which is the whole point
      # of the finding.
      english = I18n.with_locale(:en) { render_rows(filter_row) && rendered_content }
      chinese = I18n.with_locale(:"zh-CN") { render_rows(filter_row) && rendered_content }
      expect(english).not_to eq(chinese)
    end

    it "words the config settings it knows and falls back for the ones it does not" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Total", "field" => "config",
            "config_key" => "filter",
            "before" => nil,
            "after" => { "slug" => "amount", "wobble" => "x" },
            "breaking" => false
          }
        ]
      )

      expect(page).to have_css(
        "code",
        text: [
          t("pair", label: t("config_fields.slug"), value: "amount"),
          t("pair", label: t("config_field_other"), value: "x")
        ].join(t("list_separator")),
        exact_text: true
      )
    end

    # "Total" in the sense that matters: no shape reaches the screen as
    # `inspect` output, however deeply or oddly it is nested.
    it "degrades an unanticipated shape to worded output rather than inspect output" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Total", "field" => "config",
            "config_key" => "filter",
            "before" => { "value" => [ 1, { "op" => "=" } ] },
            "after" => { "value" => { "value" => { "value" => { "value" => "buried" } } } },
            "breaking" => false
          }
        ]
      )

      expect(page).to have_css(
        "code",
        text: t("pair", label: t("config_fields.value"), value: [ "1", t("pair", label: t("config_fields.op"), value: "=") ].join(t("list_separator"))),
        exact_text: true
      )
      expect(page).to have_css("code", text: t("deep_value"))
      expect(rendered_content).not_to include("buried")
      expect(rendered_content).not_to include("=&gt;")
      expect(rendered_content).not_to include("&quot;op&quot;")
    end

    # The typed shape-dispatch arms have the same escape hatch, so none of them
    # can leak `inspect` output either.
    it "words a structured value arriving under a field that expects a scalar" do
      render_rows(
        [
          { "kind" => "attribute", "action" => "added", "name" => "Phone", "html_type" => { "op" => "=" } },
          *attribute_row("visibility", before: [ "admin" ], after: nil),
          *attribute_row("validators", before: { "op" => "=" }, after: [ { "op" => "=" } ]),
          *attribute_row("options_source", before: [ "static" ], after: nil),
          *attribute_row("readonly", before: { "op" => "=" }, after: nil),
          *attribute_row("type", before: { "op" => "=" }, after: nil)
        ]
      )

      expect(page).to have_css(
        "code",
        text: t("pair", label: t("config_fields.op"), value: "="),
        exact_text: true,
        minimum: 5
      )
      expect(page).to have_css("code", text: "admin", exact_text: true)
      expect(page).to have_css("code", text: "static", exact_text: true)
      expect(rendered_content).not_to include("=&gt;")
    end

    it "reads an empty object or list as nothing set" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Total", "field" => "config",
            "config_key" => "filter", "before" => {}, "after" => [], "breaking" => false
          }
        ]
      )

      expect(page).to have_css("code", text: t("none"), count: 2)
    end

    # None of these shapes is reachable through the server's canonicalisation,
    # but a payload is model output and a structured field arriving flat must
    # read as itself rather than raise mid-transcript.
    it "reads a structured field that arrives flat as itself" do
      render_rows(
        attribute_row("visibility", before: "everyone", after: nil) +
          attribute_row("validators", before: "presence", after: nil) +
          attribute_row("options_source", before: "static list", after: nil) +
          attribute_row("readonly", before: "yes", after: nil)
      )

      [ "everyone", "presence", "static list", "yes" ].each do |value|
        expect(page).to have_css("code", text: value, exact_text: true)
      end
      expect(rendered_content).not_to include("translation missing")
    end
  end

  # The server caps what it parks on the message, so the panel is a sample of a
  # bigger change. Saying so is the difference between "here is what changes"
  # and "here is some of what changes".
  describe "a payload the server had to cut down" do
    it "says how many option changes it is not showing" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Tier", "field" => "options",
            "added" => [ "Bronze" ], "removed" => [], "relabelled" => [], "omitted" => 37,
            "breaking" => false
          }
        ]
      )

      expect(page).to have_text(row_text("options_omitted", count: 37))
      expect(page).to have_css("li", count: 2)
      expect(page).to have_css("li.text-text-muted", count: 1)
    end

    it "says how many rows it is not showing" do
      render_rows(
        [],
        plan: [
          {
            "name" => "Contact", "id" => 12, "breaking" => false, "omitted_rows" => 12,
            "rows" => [ { "kind" => "attribute", "action" => "added", "name" => "Phone", "breaking" => false } ]
          }
        ]
      )

      expect(page).to have_text(row_text("rows_omitted", count: 12))
      expect(page).to have_css("li", count: 2)
    end

    it "counts one omission in the singular" do
      render_rows(
        [],
        plan: [
          {
            "name" => "Contact", "id" => 12, "breaking" => false, "omitted_rows" => 1,
            "rows" => [
              {
                "kind" => "attribute", "action" => "modified", "name" => "Tier", "field" => "options",
                "added" => [ "Bronze" ], "omitted" => 1, "breaking" => false
              }
            ]
          }
        ]
      )

      expect(page).to have_text(I18n.t("ai_assistant.assistant.plan.rows.options_omitted", count: 1))
      expect(page).to have_text(I18n.t("ai_assistant.assistant.plan.rows.rows_omitted", count: 1))
    end

    # Always present and `0` when nothing was dropped, so the quiet case is the
    # common one.
    it "stays quiet when the counts say nothing was dropped" do
      render_rows(
        [],
        plan: [
          {
            "name" => "Contact", "id" => 12, "breaking" => false, "omitted_rows" => 0,
            "rows" => [
              {
                "kind" => "attribute", "action" => "modified", "name" => "Tier", "field" => "options",
                "added" => [ "Bronze" ], "omitted" => 0, "breaking" => false
              }
            ]
          }
        ]
      )

      expect(page).to have_css("li", count: 1)
      expect(page).not_to have_css("li.text-text-muted")
    end

    it "keeps the omission line for a list it could not itemise at all" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Tier", "field" => "options",
            "added" => [], "removed" => [], "relabelled" => [], "omitted" => 40, "breaking" => false
          }
        ]
      )

      expect(page).to have_text(row_text("attribute_modified", name: "Tier", field: field("options")))
      expect(page).to have_text(row_text("options_omitted", count: 40))
      expect(page).to have_css("li", count: 2)
    end

    it "ignores a count that is not a number" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Tier", "field" => "options",
            "added" => [ "Bronze" ], "omitted" => "lots", "breaking" => false
          }
        ]
      )

      expect(page).to have_css("li", count: 1)
    end
  end

  # A single option label or formula is unbounded, and the panel sits in a chat
  # bubble.
  describe "values too long for the panel" do
    let(:cap) { described_class::MAX_VALUE_LENGTH }

    def chips = page.all("code").map(&:text)

    it "clips a long value and marks that it clipped it" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Notes", "field" => "description",
            "before" => "a" * 400, "after" => "b" * 400, "breaking" => false
          }
        ]
      )

      expect(chips).to all(satisfy { |chip| chip.length <= cap + 2 })
      expect(chips).to all(end_with(described_class::ELLIPSIS))
      expect(chips.uniq.size).to eq(2)
    end

    # The thing truncation must never do: make two different values read as the
    # same one. The window follows the difference out past the cap.
    it "still shows two values differing past the cap as different" do
      before = "#{'same ' * 50}old tail"
      after = "#{'same ' * 50}new tail"

      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Formula", "field" => "formula",
            "before" => before, "after" => after, "breaking" => false
          }
        ]
      )

      expect(before.length).to be > cap
      expect(before[0, cap]).to eq(after[0, cap])
      expect(chips.uniq.size).to eq(2)
      expect(chips.first).to include("old tail")
      expect(chips.last).to include("new tail")
      expect(chips).to all(start_with(described_class::ELLIPSIS))
    end

    it "clips a relabelled option pair without hiding which part changed" do
      before = "#{'Tier ' * 40}Gold"
      after = "#{'Tier ' * 40}Platinum"

      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Tier", "field" => "options",
            "added" => [ "x" * 300 ], "removed" => [], "relabelled" => [ { "before" => before, "after" => after } ],
            "breaking" => false
          }
        ]
      )

      expect(page).to have_css("code", text: "Gold")
      expect(page).to have_css("code", text: "Platinum")
      expect(chips).to all(satisfy { |chip| chip.length <= cap + 2 })
    end

    it "clips a name long enough to crowd out the change itself" do
      render_rows(
        [],
        plan: [
          {
            "name" => "N" * 400, "id" => 12, "breaking" => false,
            "rows" => [ { "kind" => "attribute", "action" => "added", "name" => "P" * 400, "breaking" => false } ]
          }
        ]
      )

      expect(page.find("li").text.length).to be < 400
      expect(page.find("p.text-xs.font-semibold").text.length).to eq(cap + 1)
    end
  end

  # The payload is model output parked on a message, so nothing here may raise
  # or leak a translation key. What it may NOT do is stay quiet: the gate's
  # safety is the panel.
  describe "a payload it has no wording for" do
    # The review finding. UpdatePolicy refuses to apply any document whose plan
    # is non-empty, so a row this component declines to render is a change the
    # admin approves without ever seeing it. An unrecognised field is a wording
    # gap, not a reason to hide a write.
    it "renders a row whose field it does not recognise rather than dropping it" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Email", "field" => "secret_column",
            "before" => "old", "after" => "new", "breaking" => false
          },
          { "kind" => "identity", "action" => "modified", "field" => "secret_column", "after" => "x" }
        ]
      )

      expect(page).to have_css("li", count: 2)
      expect(page).to have_text(row_text("attribute_modified", name: "Email", field: t("field_other")))
      expect(page).to have_text(row_text("identity_modified", field: t("field_other")))
      expect(page).to have_css("code", text: "old")
      expect(page).to have_css("code", text: "new")
      expect(rendered_content).not_to include("translation missing")
      expect(rendered_content).not_to include("secret_column")
    end

    it "renders a config row whose setting it does not recognise" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Amount", "field" => "config",
            "config_key" => "wobble", "before" => 1, "after" => 2, "breaking" => false
          }
        ]
      )

      expect(page).to have_css("li", count: 1)
      expect(page).to have_text(row_text("attribute_modified", name: "Amount", field: t("config_field_other")))
      expect(rendered_content).not_to include("wobble")
    end

    it "names a kind, action, or nameless row it has no sentence for" do
      render_rows(
        [
          { "kind" => "wormhole", "action" => "modified", "name" => "Contact" },
          { "kind" => "attribute", "action" => "deleted", "name" => "Email" },
          { "kind" => "attribute", "action" => "added", "name" => "" },
          { "kind" => "group", "action" => "added" }
        ]
      )

      expect(page).to have_css("li", count: 4)
      expect(page).to have_text(row_text("other"))
      expect(rendered_content).not_to include("translation missing")
      expect(rendered_content).not_to include("wormhole")
    end

    # Structural junk is the one thing still dropped — and dropping it must not
    # cost the entry the rows it does have.
    it "drops junk without taking the real rows with it" do
      render_rows(
        [
          "not a hash",
          nil,
          7,
          { "kind" => "attribute", "action" => "added", "name" => "Phone", "breaking" => false }
        ]
      )

      expect(page).to have_css("li", count: 1)
      expect(page).to have_text(row_text("attribute_added", name: "Phone"))
    end

    # The paired half of a server-side guarantee, not a standalone preference.
    #
    # An empty card under "I need your confirmation" would ask the admin to
    # approve a change list that is not there. The server never parks a
    # proposal it cannot describe — ChangePlan skips blank-keyed rows, and
    # schema validation runs before the confirmation gate — but the plan is
    # what makes the gate safe, so when an entry does arrive undescribable the
    # answer is to say so, not to render nothing. That keeps "confirmation
    # prompt with no panel under it" unreachable from this side whatever the
    # entry holds.
    it "says an entry cannot be described rather than rendering nothing (see ChangePlan)" do
      component = described_class.new(
        proposal: proposal(
          [],
          plan: [
            {
              "name" => "Contact", "id" => 12, "breaking" => true,
              "rows" => [ "junk", nil ]
            }
          ]
        )
      )

      expect(component.render?).to be(true)

      render_inline(component)

      expect(page).to have_css("[data-proposal='pending']")
      expect(page).to have_text(t("title"))
      expect(page).to have_text(row_text("unplannable"))
      expect(page).to have_css("li.bg-warning-subtle", count: 1)
    end

    # The server's own signal for the same situation: it could not work out
    # what applying the document would do, but it is gating the write on it.
    it "explains an entry the server marked unplannable" do
      render_rows(
        [],
        plan: [
          { "name" => "Contact", "id" => 12, "breaking" => true, "rows" => [], "unplannable" => true }
        ]
      )

      expect(page).to have_css("[data-proposal='pending']")
      expect(page).to have_text("Contact")
      expect(page).to have_text(row_text("unplannable"))
      expect(page).to have_text(t("breaking_badge"))
      expect(page).to have_css("[data-proposal-apply]")
    end
  end

  describe "the breaking-change warning" do
    it "flags a proposal that can affect existing entries" do
      render_rows(
        [
          {
            "kind" => "attribute", "action" => "modified", "name" => "Email", "field" => "html_type",
            "before" => "text", "after" => "email", "breaking" => true
          },
          { "kind" => "attribute", "action" => "added", "name" => "Phone", "breaking" => false }
        ]
      )

      expect(page).to have_text(t("breaking_badge"))
      expect(page).to have_css("li.bg-warning-subtle.text-warning", count: 1)
      expect(page).to have_css("li.text-text-secondary", count: 1)
    end

    it "stays quiet when nothing is breaking" do
      render_rows([ { "kind" => "attribute", "action" => "added", "name" => "Phone", "breaking" => false } ])

      expect(page).not_to have_text(t("breaking_badge"))
      expect(page).not_to have_css(".bg-warning-subtle")
    end

    # Only a real boolean counts: a stringly-typed flag would otherwise raise a
    # warning on every row.
    it "does not take a non-boolean flag as breaking" do
      render_rows([ { "kind" => "attribute", "action" => "added", "name" => "Phone", "breaking" => "false" } ])

      expect(page).not_to have_text(t("breaking_badge"))
    end
  end

  describe "what the footer offers" do
    let(:rows) { [ { "kind" => "attribute", "action" => "added", "name" => "Phone", "breaking" => false } ] }

    def render_state(state)
      render_inline(described_class.new(proposal: proposal(rows), state: state))
    end

    # Apply posts the confirm phrase pinned to this message through the
    # ordinary message pipeline.
    it "offers Apply and refine while the proposal is pending, without Discard until a path is given" do
      render_state(:pending)

      expect(page).to have_css("[data-proposal='pending']")
      expect(page).to have_text(t("subtitle"))
      apply = page.find("button[data-action='click->ai-assistant#applyProposal']")
      expect(apply[:type]).to eq("button")
      expect(apply["data-ai-assistant-reply-param"]).to eq(t("apply_reply"))
      expect(apply).to have_css("[data-proposal-apply-label]", text: t("apply"))
      expect(apply["data-proposal-apply"]).to eq("")
      expect(apply["data-ai-assistant-message-id-param"]).to be_blank
      expect(page).not_to have_css("[data-proposal-discard]")
      refine_button = page.find("button[data-action='click->ai-assistant#refineProposal']")
      expect(refine_button[:type]).to eq("button")
      expect(refine_button.text.strip).to eq(t("refine"))
      expect(refine_button["data-proposal-refine"]).to eq("")
      # The slot the controller writes into once a newer proposal lands.
      expect(page).to have_css("[data-proposal-note].hidden", visible: :all)
      expect(page).not_to have_text(t("applied"))
    end

    it "pins Apply to a message and posts Discard when a path is given" do
      render_inline(
        described_class.new(
          proposal: proposal(rows),
          state: :pending,
          message_id: 99,
          discard_path: "/81721200/admin/modules/ai_assistant/messages/99/discard_proposal"
        )
      )

      apply = page.find("button[data-action='click->ai-assistant#applyProposal']")
      expect(apply["data-ai-assistant-message-id-param"]).to eq("99")
      host = page.find("[data-proposal-discard]")
      expect(host.tag_name).to eq("span")
      expect(host[:class]).to eq("contents")
      form = host.find("form")
      expect(form[:action]).to eq("/81721200/admin/modules/ai_assistant/messages/99/discard_proposal")
      expect(form[:method]).to eq("post")
      expect(form).not_to have_css("[data-turbo-confirm]")
      expect(form["data-proposal-discard"]).to be_blank
      button = form.find("button, input[type='submit']")
      expect(button["data-proposal-discard"]).to be_blank
      expect(button["data-turbo-submits-with"]).to eq(t("discarding"))
      expect(button.text.strip).to eq(t("discard"))
      html = rendered_content
      expect(html.index("data-proposal-apply")).to be < html.index("data-proposal-discard")
      expect(html.index("data-proposal-discard")).to be < html.index("data-proposal-refine")
    end

    it "explains a discarded proposal and offers nothing" do
      render_state(:declined)

      expect(page).to have_css("[data-proposal='declined']", count: 1, text: t("declined"))
      expect(page).not_to have_css("button")
      expect(page).not_to have_text(t("subtitle"))
    end

    it "stamps an applied proposal and offers nothing" do
      render_state(:applied)

      expect(page).to have_css("[data-proposal='applied']")
      expect(page).to have_text(t("applied"))
      expect(page).not_to have_text(t("subtitle"))
      expect(page).not_to have_css("button")
      expect(page).not_to have_css("[data-proposal-apply]")
    end

    it "explains a proposal a newer one has replaced" do
      render_state(:superseded)

      expect(page).to have_css("[data-proposal='superseded']")
      expect(page).to have_css("[data-proposal-note]", text: t("superseded"))
      expect(page).not_to have_css("[data-proposal-note].hidden", visible: :all)
      expect(page).not_to have_css("button")
      expect(page).not_to have_text(t("subtitle"))
    end

    it "treats a state it does not recognise as still pending" do
      render_state(:half_applied)

      expect(page).to have_css("[data-proposal='pending']")
      expect(page).to have_css("[data-proposal-apply]")
    end
  end

  it "gives the card an accessible name and keeps long values inside it" do
    render_rows(
      [
        {
          "kind" => "attribute", "action" => "modified", "name" => "Notes", "field" => "description",
          "before" => "a" * 200, "after" => "b" * 200, "breaking" => false
        }
      ]
    )

    expect(page).to have_css("section[aria-label='#{t("title")}']")
    expect(page).to have_css("section.max-w-\\[min\\(92\\%\\,42rem\\)\\].rounded-xl.ring-1.ring-border-subtle")
    expect(page).to have_css("code.break-words", count: 2)
  end

  # Apply works by sending a phrase the server already treats as confirmation,
  # so a phrase outside that list would silently start an ordinary chat turn.
  it "confirms with a phrase every locale already accepts" do
    %i[en zh-CN].each do |locale|
      tokens = I18n.t("ai_assistant.assistant.confirmation_tokens", locale: locale)
      expect(tokens).to include(I18n.t("ai_assistant.assistant.plan.apply_reply", locale: locale))
    end
  end

  it "translates every row and field label in both locales" do
    keys = %i[
      title subtitle breaking_badge apply applying refine applied superseded discard discarding
      declined none apply_reply
      list_separator audiences_none field_other config_field_other deep_value
    ]

    %i[en zh-CN].each do |locale|
      keys.each do |key|
        expect(I18n.t("ai_assistant.assistant.plan.#{key}", locale: locale, default: nil)).to be_present
      end
      expect(I18n.t("ai_assistant.assistant.plan.fields", locale: locale).keys)
        .to match_array(described_class::FIELDS.map(&:to_sym))
      expect(I18n.t("ai_assistant.assistant.plan.config_fields", locale: locale).keys)
        .to match_array(described_class::CONFIG_FIELDS.map(&:to_sym))
      expect(I18n.t("ai_assistant.assistant.plan.rows", locale: locale).keys).to match_array(
        %i[
          identity_modified attribute_added attribute_removed attribute_modified
          attribute_options_added attribute_options_removed attribute_options_relabelled
          group_added group_modified group_removed
          association_added association_modified association_removed
          default_properties_modified other unplannable
          options_omitted rows_omitted
        ]
      )
      expect(I18n.t("ai_assistant.assistant.plan.boolean", locale: locale).keys).to match_array(%i[true false])
      expect(I18n.t("ai_assistant.assistant.plan.options_source", locale: locale).keys)
        .to match_array(%i[static entity other])
      expect(I18n.t("ai_assistant.assistant.plan.values", locale: locale).keys).to match_array(%i[type storage])
    end
  end

  # The component's field allowlist is a second, independent copy of what the
  # server can emit — that is what lets plan_field_labels_spec.rb catch drift
  # between them. This pins the copy itself so a field added there is noticed
  # here too.
  it "carries wording for exactly the fields the plan can emit" do
    plan = EntityDefinitions::Assistant::ChangePlan

    expect(described_class::FIELDS).to match_array(plan.identity_fields | plan.attribute_fields)
  end

  # The bounded set `config_key` is drawn from, plus the keys inside the object
  # values some of those settings hold.
  it "carries wording for every config setting the normalizer allows" do
    allowlist = EntityDefinitions::Normalizer::INPUT_CONFIG_KEYS |
                EntityDefinitions::Normalizer::COMPUTED_CONFIG_KEYS

    expect(described_class::CONFIG_FIELDS).to include(*allowlist)
    expect(described_class::CONFIG_FIELDS).to include("slug", "op", "value", "default")
  end

  # The flowchart path parks a proposal with no plan, so it renders no panel and
  # has to say in words what the entity copy says by pointing at one.
  it "gives the flowchart gate its own confirmation wording in both locales" do
    %i[en zh-CN].each do |locale|
      entity = I18n.t("ai_assistant.assistant.update_needs_confirmation", locale: locale, default: nil)
      flowchart = I18n.t("ai_assistant.assistant.flowchart_needs_confirmation", locale: locale, default: nil)

      expect(flowchart).to be_present
      expect(flowchart).not_to eq(entity)
    end
  end
end
