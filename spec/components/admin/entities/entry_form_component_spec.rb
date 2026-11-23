# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::EntryFormComponent, type: :component do
  def field(slug, **attributes)
    double("Field", **{
      slug: slug, label: slug == "title" ? "Course title" : "Internal notes",
      help_text: nil, html_type: "text", required: false, options: [], constraints: {},
      full_width: false, invalid_literal: false
    }.merge(attributes))
  end

  let(:title_field) { field("title", required: true) }
  let(:notes_field) { field("notes", html_type: "textarea") }
  let(:groups) do
    [
      double("Group", key: "identity", label: "Course details", fields: [title_field]),
      double("Group", key: "empty", label: "Excluded", fields: []),
      double("Group", key: "other", label: nil, fields: [notes_field])
    ]
  end
  let(:values) { { "title" => "Attempted title", "notes" => "" } }
  let(:errors) { {} }
  let(:available) { true }
  let(:blockers) { [] }
  let(:form) do
    double("EntryForm", groups: groups, errors: errors, available?: available, blockers: blockers).tap do |form|
      allow(form).to receive(:value_for) { |slug| values[slug] }
      allow(form).to receive(:errors_for) { |slug| errors.fetch(slug, []) }
    end
  end

  def render_form
    render_inline(described_class.new(form: form, url: "/123/admin/entities/7/entries", cancel_path: "/123/admin/entities/7"))
  end

  it "posts to the supplied creation URL with full-page navigation and schema field order" do
    rendered = render_form
    html_form = rendered.at_css("form")
    expect(html_form["action"]).to eq("/123/admin/entities/7/entries")
    expect(html_form["method"]).to eq("post")
    expect(html_form["data-turbo-frame"]).to eq("_top")
    expect(rendered.css("input:not([type='hidden']), textarea").map { |control| control["name"] }).to eq(["entry[data][title]", "entry[data][notes]"])
    expect(rendered.at_css("input#entry_title")["value"]).to eq("Attempted title")
    expect(rendered.at_css("textarea#entry_notes").text).to eq("")
  end

  it "omits empty groups and composes divided, accent-headed fieldsets with a translated ungrouped legend" do
    rendered = render_form
    expect(rendered.css("fieldset > legend").map(&:text)).to eq(["Course details", I18n.t("admin_misc.entities.entry_detail.ungrouped")])
    expect(rendered.css("fieldset > legend").all? { |legend| legend["class"].include?("border-l-2 border-accent-muted pl-3") }).to be(true)
    expect(rendered.css("fieldset > div").all? { |grid| grid["class"].include?("grid-cols-1 gap-x-4 gap-y-5 md:grid-cols-2") }).to be(true)
    expect(rendered.css("hr").size).to eq(1)
    expect(rendered.at_css("hr").next_element.at_css("legend").text).to eq(I18n.t("admin_misc.entities.entry_detail.ungrouped"))
    expect(rendered.css(".card")).to be_empty
    expect(rendered.css("[role='alert'], [autofocus]")).to be_empty
  end

  it "renders one unnamed primary submit before Cancel with translated pending copy" do
    rendered = render_form
    button = rendered.at_css("button[type='submit']")
    expect(rendered.css("button[type='submit']").size).to eq(1)
    expect(button["name"]).to be_nil
    expect(button["disabled"]).to be_nil
    expect(button.text.strip).to eq(I18n.t("admin_misc.entities.entry_form.create"))
    expect(button["data-turbo-submits-with"]).to eq(I18n.t("admin_misc.entities.entry_form.submitting"))
    cancel = button.next_element
    expect(cancel.name).to eq("a")
    expect(cancel["href"]).to eq("/123/admin/entities/7")
    expect(cancel.text.strip).to eq(I18n.t("common.actions.cancel"))
    expect([button, cancel].all? { |control| control["class"].include?("min-h-11 w-full sm:w-auto") }).to be(true)
  end

  it "uses a supplied submit label and renders no Cancel for a page form without a cancel path" do
    rendered = render_inline(described_class.new(form: form, url: "/123/admin/entities/7/entries", submit_label: "Create and link"))

    expect(rendered.css("button[type='submit']").map { |node| node.text.strip }).to eq(["Create and link"])
    expect(rendered.at_css("button[type='submit']")["data-turbo-submits-with"]).to eq(I18n.t("admin_misc.entities.entry_form.submitting"))
    expect(rendered.css("a, button[type='button']")).to be_empty
  end

  it "cancels a page form inside an in-page modal by running the supplied dismiss action" do
    rendered = render_inline(described_class.new(form: form, url: "/123/admin/entities/7/entries", dismiss_action: "modal-dialog#close"))

    cancel = rendered.at_css("button[data-action='modal-dialog#close']")
    expect(cancel["type"]).to eq("button")
    expect(cancel.text.squish).to eq(I18n.t("common.actions.cancel"))
    expect(rendered.at_css("form")["data-turbo-frame"]).to eq("_top")
    expect(rendered.css("a")).to be_empty
  end

  it "saves an existing entry with PATCH and Save Changes copy" do
    rendered = render_inline(described_class.new(form: form, url: "/123/admin/entities/7/entries/9", http_method: :patch,
                                                 cancel_path: "/123/admin/entities/7"))
    html_form = rendered.at_css("form")
    expect(html_form["action"]).to eq("/123/admin/entities/7/entries/9")
    expect(html_form["method"]).to eq("post")
    expect(rendered.at_css("input[type='hidden'][name='_method']")["value"]).to eq("patch")
    button = rendered.at_css("button[type='submit']")
    expect(button.text.strip).to eq(I18n.t("admin_misc.entities.entry_form.update"))
    expect(button["data-turbo-submits-with"]).to eq(I18n.t("admin_misc.entities.entry_form.updating"))
    expect(rendered.at_css("input#entry_title")["value"]).to eq("Attempted title")
  end

  context "on a failed attempt" do
    let(:errors) do
      { "title" => ["cannot be blank", "is too short"], "base" => [I18n.t("admin_misc.entities.entry_form.errors.save_failed")], "derived_total" => ["must be greater than zero"] }
    end

    it "focuses a linked summary using descriptor labels and retains nonrendered errors" do
      rendered = render_form
      summary = rendered.at_css("[role='alert']")
      expect(summary["tabindex"]).to eq("-1")
      expect(summary["autofocus"]).to eq("autofocus")
      expect(summary["aria-labelledby"]).to eq("entry_errors_heading")
      expect(summary.at_css("h2").text).to eq(I18n.t("admin_misc.entities.entry_form.errors_heading"))
      expect(summary.css("a[href='#entry_title']").size).to eq(2)
      expect(summary.css("a").text).to include("Course title")
      expect(summary.text).to include(errors["base"].first, "must be greater than zero")
      expect(summary.css("li").size).to eq(4)
      expect(summary.css("a[href='#entry_derived_total'], a[href='#entry_base']")).to be_empty
      summary.css("a").each { |link| expect(rendered.at_css(link["href"])).not_to be_nil }
      expect(rendered.css("input[name='entry[data][derived_total]']")).to be_empty
    end
  end

  context "with an unsupported visible writable field" do
    let(:available) { false }
    let(:blockers) { [double("Field", label: '<img src=x>'), double("Field", label: "Attachment")] }

    it "explains unsupported fields, retains supported controls and disables only the submit" do
      rendered = render_form
      expect(rendered.at_css("[role='status']").text).to eq(I18n.t("admin_misc.entities.entry_form.unsupported_fields", fields: "<img src=x>, Attachment"))
      expect(rendered.at_css("button[type='submit']")["disabled"]).to eq("disabled")
      expect(rendered.at_css("input#entry_title")).not_to be_nil
      expect(rendered.at_css("a[href='/123/admin/entities/7']")).not_to be_nil
      expect(rendered.css("img")).to be_empty
    end
  end

  context "with no writable fields" do
    let(:available) { false }
    let(:groups) { [] }

    it "renders the translated empty notice and disabled submit" do
      rendered = render_form
      expect(rendered.at_css("[role='status']").text).to eq(I18n.t("admin_misc.entities.entry_form.no_fields"))
      expect(rendered.at_css("button[type='submit']")["disabled"]).to eq("disabled")
      expect(rendered.css("fieldset")).to be_empty
    end
  end

  it "renders the new platform wording in Simplified Chinese while retaining authored schema labels" do
    rendered = I18n.with_locale(:"zh-CN") { render_form }
    expect(rendered.at_css("button").text.strip).to eq("创建条目")
    expect(rendered.at_css("button")["data-turbo-submits-with"]).to eq("正在创建…")
    expect(rendered.css("legend").text).to include("Course details", "其他字段")
  end

  context "with real backend form values" do
    let(:customer) { create(:customer) }
    let(:actor) { create(:user, :admin, customer: customer) }
    let(:schema) do
      [
        { "name" => "Title", "name_slug" => "title", "validators" => [{ "type" => "presence" }] },
        { "name" => "Optional credits", "name_slug" => "credits", "html_type" => "number",
          "validators" => [{ "type" => "numericality" }] },
        { "name" => "Checked", "name_slug" => "checked", "html_type" => "checkbox" },
        { "name" => "Enabled", "name_slug" => "enabled", "html_type" => "switch" }
      ]
    end
    let(:defaults) { { "title" => "Default title", "credits" => "+1", "checked" => "on", "enabled" => "on" } }
    let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json, default_properties: defaults.to_json) }
    let(:form) { Entities::EntryForm.new(entity: entity, customer: customer) }

    def expect_clean_number_attempt(rendered)
      input = rendered.at_css("input#entry_credits")
      expect(input["type"]).to eq("text")
      expect(input["value"]).to eq("+1")
      expect(input["inputmode"]).to eq("decimal")
      expect(input["required"]).to be_nil
      expect(input["aria-invalid"]).to be_nil
      expect(input["class"]).not_to include("border-danger")
      expect(rendered.css("#entry_credits_errors")).to be_empty
      expect(form.errors_for("credits")).to be_empty
    end

    it "checks checkbox and switch controls from recognized on defaults" do
      rendered = render_form
      expect(form.errors).to be_empty
      %w[checked enabled].each do |slug|
        input = rendered.at_css("input#entry_#{slug}[type='checkbox']")
        expect(input["checked"]).to eq("checked")
        expect(input["value"]).to eq("1")
        expect(rendered.at_css("input[type='hidden'][name='entry[data][#{slug}]']")["value"]).to eq("0")
      end
    end

    it "preserves a server-valid optional +1 default through a text input without inventing an error" do
      rendered = render_form
      expect(form.errors).to be_empty
      expect_clean_number_attempt(rendered)
      expect(rendered.css("[role='alert']")).to be_empty
    end

    %w[on off].each do |literal|
      context "after a failed POST containing #{literal}" do
        let(:defaults) { super().merge("checked" => literal == "on" ? "off" : "on", "enabled" => literal == "on" ? "off" : "on") }
        let(:form) do
          signal, context = Entities::Activities::CreateEntry.call(
            customer: customer, actor: actor, entity: entity,
            params: { "title" => "", "credits" => "+1", "checked" => literal, "enabled" => literal }
          )
          expect(signal.to_h[:semantic]).to eq(:failure)
          context.fetch(:form)
        end

        it "retains the submitted boolean states and valid +1 attempt when another field fails" do
          rendered = render_form
          expect(form.errors.keys).to eq(["title"])
          expect(rendered.css("[role='alert'] a[href='#entry_title']")).not_to be_empty
          %w[checked enabled].each do |slug|
            input = rendered.at_css("input#entry_#{slug}[type='checkbox']")
            expect(input["checked"]).to eq(literal == "on" ? "checked" : nil)
            expect(input["value"]).to eq("1")
            expect(input["required"]).to be_nil
            expect(input["aria-invalid"]).to be_nil
            expect(rendered.at_css("input[type='hidden'][name='entry[data][#{slug}]']")["value"]).to eq("0")
          end
          expect_clean_number_attempt(rendered)
        end
      end
    end
  end

  it "keeps UI and backend error keys in locale parity while reusing the existing ungrouped label" do
    translations = %w[en zh-CN].map do |locale|
      entities = YAML.safe_load_file(Rails.root.join("config/locales/admin_misc.#{locale}.yml")).fetch(locale).dig("admin_misc", "entities")
      expect(entities.dig("entry_detail", "ungrouped")).to eq(locale == "en" ? "Other fields" : "其他字段")
      entities.fetch("entry_form")
    end
    flatten = lambda do |hash, prefix = []|
      hash.flat_map do |key, value|
        path = prefix + [key]
        value.is_a?(Hash) ? flatten.call(value, path).to_a : [[path.join("."), value]]
      end.to_h
    end
    leaves = translations.map { |translation| flatten.call(translation) }
    expected = %w[create title description submitting errors_heading unsupported_fields no_fields created
                  update updating edit_breadcrumb edit_title edit_description updated
                  errors.invalid_shape errors.invalid_choice errors.invalid_number errors.invalid_date errors.invalid_datetime errors.invalid_boolean
                  errors.rejected_value errors.save_failed errors.update_failed]
    leaves.each do |locale_leaves|
      expect(locale_leaves.keys).to match_array(expected)
      expect(locale_leaves.values).to all(be_a(String).and(be_present))
    end
    tokens = leaves.map { |locale_leaves| locale_leaves.transform_values { |text| text.scan(/%\{([^}]+)\}/).flatten.sort } }
    expect(tokens[0]).to eq(tokens[1])
    expect(tokens[0].slice("title", "description", "unsupported_fields", "errors.rejected_value", "edit_title")).to eq(
      "title" => ["name"], "description" => ["name"], "unsupported_fields" => ["fields"], "errors.rejected_value" => ["value"],
      "edit_title" => %w[id name]
    )
  end

  describe "frame mode (quick-add dialog)" do
    it "submits into the enclosing frame and cancels by closing the dialog" do
      rendered = render_inline(described_class.new(form: form, url: "/123/admin/entities/7/entries?label_field=title", frame: true))

      expect(rendered.at_css("form")["action"]).to eq("/123/admin/entities/7/entries?label_field=title")
      expect(rendered.at_css("form")["data-turbo-frame"]).to be_nil
      cancel = rendered.at_css("button[data-action='entity-quick-add-dialog#close']")
      expect(cancel["type"]).to eq("button")
      expect(cancel.text.squish).to eq(I18n.t("common.actions.cancel"))
      expect(rendered.css("a[href]")).to be_empty
    end

    context "with a nested level's id prefix and errors" do
      let(:errors) { { "title" => ["cannot be blank"] } }

      it "scopes control, label, error and summary ids so they never clash with the page form" do
        rendered = render_inline(described_class.new(form: form, url: "/123/admin/entities/7/entries", frame: true,
                                                     id_prefix: "entry_quick_add_0"))

        expect(rendered.at_css("input#entry_quick_add_0_title")["name"]).to eq("entry[data][title]")
        expect(rendered.at_css("label[for='entry_quick_add_0_title']")).to be_present
        expect(rendered.at_css("#entry_quick_add_0_title_errors")).to be_present
        expect(rendered.at_css("[role='alert']")["aria-labelledby"]).to eq("entry_quick_add_0_errors_heading")
        expect(rendered.at_css("h2#entry_quick_add_0_errors_heading")).to be_present
        expect(rendered.at_css("[role='alert'] a")["href"]).to eq("#entry_quick_add_0_title")
        expect(rendered.css("[id^='entry_title'], #entry_errors_heading")).to be_empty
      end
    end
  end

  describe "+ Add New on reference dropdowns" do
    let(:customer) { create(:customer) }
    let(:teacher) do
      create(:entity, customer: customer, name: "Teacher", display_label: "Tutor",
                      property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    end
    let(:course_schema) do
      [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" },
       reference("teacher", "select"), reference("assistants", "multi-select"), reference("mentor", "radio")]
    end
    let(:course) { create(:entity, customer: customer, name: "Course", property_schema: course_schema.to_json) }
    let(:form) { Entities::EntryForm.new(entity: course, customer: customer) }
    let!(:smith) { create(:entity_entry, customer: customer, entity: teacher, data: { "name" => "Smith" }.to_json) }

    def reference(slug, html_type)
      { "name" => slug.capitalize, "name_slug" => slug, "html_type" => html_type,
        "config" => { "options_source" => "entity_entries", "entity_id" => teacher.id.to_s, "label_field" => "name" } }
    end

    def render_at(depth)
      render_inline(described_class.new(form: form, url: "/#{customer.id}/admin/entities/#{course.id}/entries",
                                        cancel_path: "/#{customer.id}/admin/entities/#{course.id}", quick_add_depth: depth))
    end

    it "ends a single-select reference with + Add New, wired to the level's dialog rendered after the form" do
      rendered = render_at(1)

      wrapper = rendered.at_css("form [data-controller='entity-quick-add']")
      expect(wrapper["data-entity-quick-add-url-value"])
        .to eq("/#{customer.id}/admin/entities/#{teacher.id}/entries/new?label_field=name")
      expect(wrapper["data-entity-quick-add-title-value"]).to eq(I18n.t("admin_misc.entities.quick_add.title", name: "Tutor"))
      expect(wrapper["data-entity-quick-add-entity-quick-add-dialog-outlet"]).to eq("#entity-quick-add-dialog-1")
      select = wrapper.at_css("select#entry_teacher")
      expect(select["name"]).to eq("entry[data][teacher]")
      expect(select.css("option").map(&:text))
        .to eq([I18n.t("comp_form_fields.select.blank_option"), "Smith", I18n.t("admin_misc.entities.quick_add.option")])
      expect(select.css("option").last["data-quick-add-option"]).to eq("true")

      expect(rendered.css("[data-controller='entity-quick-add']").size).to eq(1)
      expect(rendered.at_css("form dialog")).to be_nil
      expect(rendered.at_css("form + dialog#entity-quick-add-dialog-1 turbo-frame#entity-quick-add-frame-1")).to be_present
    end

    it "leaves the dropdown and page without quick add when no depth is given" do
      rendered = render_at(nil)

      expect(rendered.css("[data-controller='entity-quick-add'], dialog, option[data-quick-add-option]")).to be_empty
    end

    it "stops offering + Add New past the deepest dialog level" do
      rendered = render_at(Admin::Entities::QuickAddDialogComponent::MAX_DEPTH + 1)

      expect(rendered.css("[data-controller='entity-quick-add'], dialog")).to be_empty
      expect(rendered.at_css("select#entry_teacher option[value='#{smith.id}']")).to be_present
    end

    context "without single-select references" do
      let(:course_schema) { [reference("assistants", "multi-select"), reference("mentor", "radio")] }

      it "renders no dialog" do
        expect(render_at(0).css("dialog, [data-controller='entity-quick-add']")).to be_empty
      end
    end

    it "translates the add-new option in Simplified Chinese" do
      rendered = I18n.with_locale(:"zh-CN") { render_at(0) }

      expect(rendered.css("select#entry_teacher option").last.text).to eq("+ 新增")
    end
  end
end
