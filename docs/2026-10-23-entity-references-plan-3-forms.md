# Entity References Implementation Plan (Plan 3 of 3): Form Lifecycle

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A launched form can always accept its submissions, and an admin can see when it can't:

- launch is refused when a dropdown would be empty, a required field is missing from the form, or the submission process is offline;
- trashing an entity takes its live forms offline, and restoring it says which forms are still offline;
- a flowchart that launched forms use can't be trashed, and taking it offline says how many forms stop;
- the forms list and the page header show "Can't be submitted" or "Out of date";
- generated forms leave derived fields out, carry help text, and use translated headings with a "Linked: <entity>" section for link fields;
- a section whose fields the viewer can't see disappears with its heading.

**Architecture:** `Pages::SubmissionProcess` is the one lookup for "which flowchart runs this page", shared by `Pages::PublicSubmission` and the launch checks. `Pages::LaunchChecks` holds the three checks that read beyond the page's own configuration (dropdowns, required fields, submission process). Its `Lookup` memoises entities, flowcharts and dropdown option sources, so a list of forms costs one read per distinct record. `Page#submission_blockers` is the part that makes every submission fail. `Pages::FormHealth` turns it, plus `Page#entity_out_of_date?`, into one badge status per row. `Page.bound_to_flowchart` finds forms through the global head and every tenant's override head.

**Tech Stack:** Rails 8.1.2, Ruby 3.2.8, Reform, ViewComponent, Tailwind, RSpec, SQLite `json_extract`.

**Spec:** `docs/2026-10-23-entity-references-display-lifecycle-design.md`. This plan covers §3.5, §5, §6, the Plan 3 keys in §8, and the Plan 3 rows of §9 and §10.

**Depends on:** Plan 1 (`docs/2026-10-23-entity-references-plan-1-references.md`) must be in the working tree. Plan 3 uses:

- `Page#input_fields` (Plan 1 Task 5);
- `Entities::ReferenceOptions#target` and `#usable?` (Plan 1 Task 1);
- the reference trash guard in `BridgeEntityManagement#soft_delete` (Plan 1 Task 10);
- Plan 1 Task 6's edit of `PageFieldPopulator`'s `dynamic_options` line, which Plan 3 leaves alone.

Plan 2 (`docs/2026-10-23-entity-references-plan-2-display.md`) can run in parallel. The two plans share one file, `doc/reference/{en,zh-CN}/entity-builder.md`. If Plan 2 is in progress, start Task 10 here only after Plan 2's Task 7 has finished.

## Global Constraints

- No hard-coded user-facing strings. Task 1 adds every Plan 3 key to both `en` and `zh-CN`. Every other task reuses those keys and adds none.
- Tenant-facing launch messages never say "flowchart" or "流程图". Flowchart trash and take-offline messages are owner-only (`FlowchartVisibility`) and may say it.
- No backward-compatibility shims.
- Do NOT run `git commit`. Leave changes in the working tree. `git add -N <new file>` is allowed.
- Only edit files your task owns (see the table below). If a file outside your task needs a change, stop and report it.
- Ignore `app/services/page_layout_templates/templates/**`.
- RSpec isolation: each task uses its own database, `TEST_ENV_NUMBER=<60 + task number>`. Prepare it once with `RAILS_ENV=test TEST_ENV_NUMBER=<n> bin/rails db:schema:load`, then run `TEST_ENV_NUMBER=<n> bundle exec rspec <files>`.
- Never claim tests pass without pasting the real command output.
- Subagents inherit the parent model: omit `model` (or pass `inherit`).
- Docs change in the same plan. Task 10 owns every `doc/reference/**` edit for Plan 3.
- UI: Task 7 adds badges to existing surfaces using the existing `BadgeComponent`. Before it edits markup, it consults the shadcn `badge` component through the `plugin-shadcn-shadcn` MCP tools.
- Locale parity helper, used by several tasks:

```bash
locale_parity() { for stem in "$@"; do ruby -ryaml -e 'stem=ARGV[0]; f=->(h,p=[]){h.flat_map{|k,v| v.is_a?(Hash) ? f.(v,p+[k]) : [(p+[k]).join(".")]}}; en=f.(YAML.load_file("config/locales/#{stem}.en.yml", aliases: true)["en"]); zh=f.(YAML.load_file("config/locales/#{stem}.zh-CN.yml", aliases: true)["zh-CN"]); d=(en-zh)+(zh-en); puts(d); exit(d.empty? ? 0 : 1)' "$stem" || return 1; done; }
```

## Waves and file ownership

| Wave | Task | Agent | Owns |
|---|---|---|---|
| 1 | T1 Locale keys | anysys-backend-developer | `config/locales/maint_core.{en,zh-CN}.yml`, `config/locales/admin_misc.{en,zh-CN}.yml` |
| 2 | T2 Launch checks | anysys-backend-developer | `app/services/pages/{submission_process,launch_checks}.rb` (new), `app/services/pages/public_submission.rb`, `app/models/concerns/{page_launch_lifecycle,page_entity_binding}.rb`, `spec/services/pages/launch_checks_spec.rb` (new) |
| 2 | T3 Bindings, trash cascade, flowchart guard | anysys-backend-developer | `app/models/page.rb`, `app/models/concerns/bridge_entity_management.rb`, `app/models/flowchart.rb`, `spec/models/page_bindings_spec.rb` (new), `spec/models/concerns/entity_trash_cascade_spec.rb` (new), `spec/models/flowchart_trash_guard_spec.rb` (new) |
| 2 | T4 Generator | anysys-backend-developer | `app/services/{entity_field_organizer,page_field_populator}.rb`, `app/services/page_template_applier/{field_grouper,layout_element_builder}.rb`, `spec/services/{entity_field_organizer,page_field_populator,page_field_populator_calculated,page_template_applier}_spec.rb` |
| 2 | T5 Hidden sections | anysys-backend-developer | `app/services/page_content_generator.rb`, `app/services/page_content_generator/layout_elements.rb`, `spec/services/page_content_generator_hidden_sections_spec.rb` (new) |
| 3 | T6 Audience re-check, form status, assistant | anysys-backend-developer | `app/contracts/pages/visibility_contract.rb`, `app/services/pages/form_health.rb` (new), `spec/contracts/pages/visibility_contract_spec.rb`, `spec/services/pages/form_health_spec.rb` (new), `spec/services/ai_assistant/assistant/generate_page_spec.rb` |
| 4 | T7 Badges | anysys-frontend-developer | `app/components/admin/pages/form_health_badge_component.rb` (new), `app/components/admin/pages/ops_table_component.{rb,html.erb}`, `app/views/admin/pages/index.html.erb`, `app/views/admin/maintenance/pages/show.html.erb`, `spec/components/admin/pages/{form_health_badge,ops_table}_component_spec.rb` |
| 4 | T8 Controllers | anysys-security-engineer | `app/controllers/admin/maintenance/{entities,base_restorations,entity_restorations,flowcharts,flowchart_launches,pages}_controller.rb`, `app/controllers/admin/pages_controller.rb`, `spec/requests/admin/maintenance/{entities,entity_restorations,flowcharts,flowchart_launches,pages}_spec.rb`, `spec/requests/admin/pages_spec.rb` |
| 5 | T9 Fixture sweep | anysys-qa-engineer | spec files outside the other tasks' lists, fixtures only |
| 5 | T10 Plan 3 docs | anysys-backend-developer | `doc/reference/{en,zh-CN}/{page-builder,page-rendering,flowchart-builder,entity-builder}.md` |
| 6 | T11 Verification | anysys-release-engineer | nothing (runs commands only) |

Why the waves are ordered this way:

- T1 lands every key first, so the wave-2 specs can assert on real messages.
- T2–T5 touch disjoint files. T3's `Flowchart#soft_delete` guard and T2's launch checks don't depend on each other.
- T6 needs `Pages::LaunchChecks` (T2). T7 and T8 need `Pages::FormHealth` (T6) and the T3 model methods.
- T7 and T8 run together. Until T8 sets `@form_statuses` and `@form_status`, the views render no badge, because the component treats `nil` as healthy.
- T9 runs once every production change is in, to repair fixtures that the new launch checks now reject.

## Spec coverage

| Spec | Task |
|---|---|
| §3.5 reference launch check (target, display-field visibility per audience) | T2 |
| §5.1 trash cascade, `Page.for_entity` CAST fix, `forms_taken_offline`, destroy flash | T3, T8 |
| §5.2 `restored_notice`, `offline_forms` | T8 |
| §5.3 `Page#input_fields` use, required fields, submission process, shared lookup | T2 |
| §5.3 audience changes (`VisibilityContract`) | T6 |
| §5.3 assistant-generated forms reported as skipped | T6 (spec only; `GeneratePage` already reports launch failures) |
| §5.4 `Page.bound_to_flowchart`, trash guard, destroy alert, `forms_stopped` | T3, T8 |
| §5.5 badges, `entity_out_of_date?`, preloading | T2, T6, T7, T8 |
| §6.1 generator | T4 |
| §6.2 hidden sections | T5 |
| §8 Plan 3 keys | T1 |
| §9 `page-builder`, `page-rendering`, `flowchart-builder`, `entity-builder` (trash cascade) | T10 |
| §10 Lifecycle, Generator and renderer, Components (badges) | T2–T8 |

Ten decisions apply the spec:

- **Forms go offline before the entity's status changes,** inside the same transaction. `Page#take_offline!` runs `update!`, and a shared page's `shared_page_binds_shared_entity` validation looks the entity up through `Entity.shared`. That scope hides a trashed entity, so the order matters. A failure still rolls everything back.
- **A field without a `source` counts as one of the entity's own fields,** because `Pages::FormParams#permit_parts` submits it as one.
- **A link section matches by the link entity's id or name** (`source_section`), as `FormParams#bridge_entity` does.
- **The audience re-check runs only for the audiences a change adds.** Narrowing never fails, and offline pages aren't checked until they launch.
- **Link entities' derived fields are left out too.** Nothing reaches `PageFieldPopulator`'s readonly branch any more, so the branch is deleted.
- **One `Pages::LaunchChecks::Lookup` per list.** It memoises entities, current versions, flowcharts and dropdown option sources, so the badge queries grow with distinct records, not rows.
- **`offline_forms` lists the restoring tenant's accessible forms** (`Page.accessible`), so a restore never names another tenant's forms.
- **A section heading's `property_slug` falls back to `"section"`.** A translated label such as "关联：学生" parameterizes to an empty string.
- **A divider whose label is the generator's default renders without a label, in any locale.** Today the renderer suppresses only the literal "Divider", so a zh-CN generated divider would show "分隔线" on the form.
- **`GeneratePage` needs no code change.** It already rolls back a failed launch and returns `skipped: :launch_failed` with the reason. T6 adds the spec.

---

### Task 1: Locale keys

**Agent:** anysys-backend-developer

**Files:**
- Modify: `config/locales/maint_core.en.yml`, `config/locales/maint_core.zh-CN.yml`
- Modify: `config/locales/admin_misc.en.yml`, `config/locales/admin_misc.zh-CN.yml`

**Interfaces:**
- Produces every key in spec §8 marked for Plan 3. The en and zh-CN text below is copied from the spec.

- [ ] **Step 1: `maint_core.en.yml`**

Add each block under the existing key named in its heading, keeping the file's two-space indentation.

Under `en.maint_core.errors.page_launch`, after `calculation_missing_field`:

```yaml
        reference_label_hidden: "%{field}: display field %{label} isn't visible to %{audience}, so the dropdown would be empty"
        reference_target_inactive: "%{field}: the referenced entity is missing or in the trash, so the dropdown would be empty"
        required_field_missing: "%{field} is required for %{audience} but isn't on the form"
        required_link_field_missing: "%{field} on the link to %{target} is required for %{audience} but isn't on the form"
        submission_process_offline: "This form's submission process is offline, so it can't accept submissions"
```

Under `en.maint_core.errors.validations`, after `flowchart_edit_launched`:

```yaml
        flowchart_in_use: "Cannot delete a flowchart that launched forms use: %{names}. Take those forms offline first."
```

Under `en.maint_core.flash.entities`, after `deleted`:

```yaml
        forms_taken_offline: "%{count} form(s) taken offline."
```

Under `en.maint_core.flash.entity_restorations`, after `restored`:

```yaml
        offline_forms: "These forms are still offline: %{names}. Relaunch them under Forms."
```

Under `en.maint_core.flash.flowchart_launches`, after `taken_offline`:

```yaml
        forms_stopped: "%{count} launched form(s) can't accept submissions until it is launched again."
```

Under `en.maint_core.pages` (the top-level `pages:` block, four-space indent), after `preview`:

```yaml
      generator:
        sections:
          additional: "Additional"
          other_fields: "Other Fields"
          linked: "Linked: %{name}"
        layout:
          divider: "Divider"
          spacer: "Spacer"
          heading: "Heading"
```

- [ ] **Step 2: `maint_core.zh-CN.yml`**

Add the same keys at the same paths:

```yaml
        reference_label_hidden: "%{field}：显示字段“%{label}”对%{audience}不可见，下拉列表将为空"
        reference_target_inactive: "%{field}：引用的实体不存在或已在回收站中，下拉列表将为空"
        required_field_missing: "“%{field}”对%{audience}为必填，但表单中没有该字段"
        required_link_field_missing: "与%{target}关联中的“%{field}”对%{audience}为必填，但表单中没有该字段"
        submission_process_offline: "该表单的提交流程已下线，无法接收提交"
```

```yaml
        flowchart_in_use: "无法删除已上线表单正在使用的流程图：%{names}。请先将这些表单下线。"
```

```yaml
        forms_taken_offline: "已将 %{count} 个表单下线。"
```

```yaml
        offline_forms: "以下表单仍处于下线状态：%{names}。请在“表单”中重新上线。"
```

```yaml
        forms_stopped: "%{count} 个已上线表单在流程图重新上线前无法接收提交。"
```

```yaml
      generator:
        sections:
          additional: "其他信息"
          other_fields: "其他字段"
          linked: "关联：%{name}"
        layout:
          divider: "分隔线"
          spacer: "间距"
          heading: "标题"
```

- [ ] **Step 3: `admin_misc.{en,zh-CN}.yml`**

Under `en.admin_misc.pages`, after `manage_access`:

```yaml
      cannot_submit: "Can't be submitted"
      cannot_submit_hint: "Every submission fails: %{problems}"
      out_of_date: "Out of date"
      out_of_date_hint: "Built from version %{built}; %{entity} is now on version %{current}."
```

Under `zh-CN.admin_misc.pages`, at the same place:

```yaml
      cannot_submit: "无法提交"
      cannot_submit_hint: "所有提交都会失败：%{problems}"
      out_of_date: "版本过旧"
      out_of_date_hint: "基于第 %{built} 版生成；%{entity}当前为第 %{current} 版。"
```

- [ ] **Step 4: Check parity and loading**

Run:

```bash
locale_parity maint_core admin_misc && bin/rails runner 'puts I18n.t("maint_core.pages.generator.sections.linked", name: "Student", locale: :en); puts I18n.t("maint_core.pages.generator.sections.linked", name: "学生", locale: :"zh-CN"); puts I18n.t("admin_misc.pages.cannot_submit", locale: :"zh-CN")'
```

Expected: `locale_parity` prints nothing. The runner prints `Linked: Student`, `关联：学生` and `无法提交`.

- [ ] **Step 5: Leave the changes uncommitted**

Run: `git status --short config/locales`
Expected: the four locale files are listed. Do not commit.

---

### Task 2: Launch checks

**Agent:** anysys-backend-developer

**Files:**
- Create: `app/services/pages/submission_process.rb`
- Create: `app/services/pages/launch_checks.rb`
- Modify: `app/services/pages/public_submission.rb`
- Modify: `app/models/concerns/page_launch_lifecycle.rb`
- Modify: `app/models/concerns/page_entity_binding.rb`
- Create: `spec/services/pages/launch_checks_spec.rb`

**Interfaces:**
- Consumes: `Page#input_fields` (Plan 1 T5), `Entities::ReferenceOptions#target` / `#usable?` (Plan 1 T1), and the T1 keys.
- Produces:
  - `Pages::SubmissionProcess.flowchart_id(page)`, `.find(id)`, `.flowchart_for(page)`, `.entity_mismatch?(flowchart, entity)`, `.offline?(page, entity:, flowchart:)`.
  - `Pages::LaunchChecks.new(page, lookup: Lookup.new(...))`, with `#reference_errors(audiences = page.visible_audiences)`, `#required_field_errors(audiences = …)`, `#submission_process_errors` and `#submission_blockers`.
  - `Pages::LaunchChecks::Lookup.new(customer_id)`, with `#entity_for(page)`, `#accessible_entity(id)`, `#current_version(entity)`, `#flowchart(id)` and `#reference_options(config, audience)`.
  - `Page#submission_blockers(lookup: nil)` and `Page#entity_out_of_date?(current_version = entity&.resolved_current_version)`.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=62 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing spec**

Create `spec/services/pages/launch_checks_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::LaunchChecks do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let(:required) { [{ "type" => "presence" }] }
  let(:hidden_from_members) { { "admin" => true, "member" => false, "public" => false } }

  around { |example| Current.set(customer: customer) { example.run } }

  # Definitions are written without validation so fixtures can hold derived
  # fields and associations without satisfying the editor's rules.
  def define(name, schema, associations: [], **attributes)
    entity = create(:entity, customer: customer, name: name, **attributes)
    entity.property_schema_json = schema
    entity.associations_json = associations
    entity.save!(validate: false)
    Entity.find(entity.id)
  end

  def attribute(slug, name, **extra)
    { "name" => name, "name_slug" => slug, "type" => "String", "html_type" => "text" }.merge(extra.transform_keys(&:to_s))
  end

  def input(slug, **extra)
    { "id" => "f_#{slug}", "field_type" => "text", "html_type" => "text", "property_slug" => slug,
      "property_type" => "string", "label" => slug.humanize, "source" => "entity" }.merge(extra.transform_keys(&:to_s))
  end

  def columns(*fields)
    { "id" => "cols_#{fields.size}", "field_type" => "columns", "property_type" => "layout",
      "columns" => [{ "fields" => fields }] }
  end

  def form(entity, fields, visibility: "admin", flowchart_id: nil)
    config = { "pages" => [{ "id" => "p1", "name" => "Step 1", "order" => 1, "fields" => fields }] }
    config["form_settings"] = { "flowchart_id" => flowchart_id } if flowchart_id
    page = build(:page, customer: customer, entity: entity, visibility: visibility, configuration: config.to_json)
    page.save!(validate: false)
    Page.find(page.id)
  end

  def checks(page) = described_class.new(page)
  def audience(key) = I18n.t("common.visibility.#{key}")
  def message(key, **vars) = I18n.t("maint_core.errors.page_launch.#{key}", **vars)

  describe "#reference_errors" do
    let(:instructor) { define("Instructor", [attribute("full_name", "姓名", visibility: hidden_from_members)]) }
    let(:dropdown) { { "options_source" => "entity_entries", "entity_id" => instructor.id, "label_field" => "full_name" } }
    let(:course) { define("Course", [attribute("instructor", "授课教师", html_type: "select", config: dropdown)]) }

    def instructor_field(**extra)
      input("instructor", label: "授课教师", html_type: "select", dynamic_options: dropdown, **extra)
    end

    it "blocks a dropdown whose display field an audience of the form can't see" do
      page = form(course, [instructor_field], visibility: "member")

      expect(checks(page).reference_errors).to eq([
        message(:reference_label_hidden, field: "授课教师", label: "姓名", audience: audience("member"))
      ])
    end

    it "passes when every audience of the form can see the display field" do
      expect(checks(form(course, [instructor_field])).reference_errors).to eq([])
    end

    it "blocks a dropdown whose target is trashed or missing, once per field" do
      ghost = input("ghost", label: "Ghost", html_type: "select", dynamic_options: dropdown.merge("entity_id" => 0))
      page = form(course, [instructor_field, ghost], visibility: "public")
      # Course still references Instructor, so the trash guard would refuse soft_delete.
      instructor.update_column(:status, Entity.statuses[:inactive])

      expect(checks(page).reference_errors).to eq([
        message(:reference_target_inactive, field: "授课教师"),
        message(:reference_target_inactive, field: "Ghost")
      ])
    end

    it "finds dropdowns inside columns containers" do
      page = form(course, [columns(instructor_field)], visibility: "member")

      expect(checks(page).reference_errors.size).to eq(1)
    end
  end

  describe "#required_field_errors" do
    let(:student) do
      define("Student", [
        attribute("full_name", "姓名", validators: required),
        attribute("email", "Email", validators: required, visibility: hidden_from_members),
        attribute("nickname", "Nickname", validators: required, default_value: "Pal"),
        attribute("motto", "Motto", validators: [{ "type" => "numericality" }]),
        attribute("double_score", "Double score", type: "Calculated", html_type: "number", formula: "1 + 1", validators: required)
      ])
    end

    it "lists each required attribute missing from the form, for every audience of the form" do
      page = form(student, [input("motto")], visibility: "member")

      expect(checks(page).required_field_errors).to eq([
        message(:required_field_missing, field: "姓名", audience: audience("admin")),
        message(:required_field_missing, field: "Email", audience: audience("admin")),
        message(:required_field_missing, field: "Nickname", audience: audience("admin")),
        message(:required_field_missing, field: "姓名", audience: audience("member")),
        message(:required_field_missing, field: "Nickname", audience: audience("member"))
      ])
    end

    it "is satisfied by fields without a source and by fields inside columns" do
      page = form(student, [input("full_name", source: nil), columns(input("email"), input("nickname"))])

      expect(checks(page).required_field_errors).to eq([])
    end

    it "does not count a base-model field with the same slug" do
      page = form(student, [input("full_name", source: "base_model"), input("email"), input("nickname")])

      expect(checks(page).required_field_errors).to eq([
        message(:required_field_missing, field: "姓名", audience: audience("admin"))
      ])
    end

    context "with a link entity" do
      let(:student) { define("Student", [attribute("full_name", "姓名")], display_label: "学生") }
      let(:course) { define("Course", [attribute("title", "Title")]) }
      let(:bridge) do
        define("assoc_course_student", [
          attribute("course", "Course", type: "EntityReference", entity_id: course.id, validators: required),
          attribute("student", "Student", type: "EntityReference", entity_id: student.id, validators: required),
          attribute("status", "Status", html_type: "select", validators: required),
          attribute("grade", "Grade", validators: required, visibility: hidden_from_members)
        ], category: :bridge)
      end
      let(:linked_course) do
        course.associations_json = [{ "target_entity_id" => student.id, "target_entity_name" => "Student",
                                      "bridge_entity_id" => bridge.id, "bridge_entity_name" => bridge.name }]
        course.save!(validate: false)
        Entity.find(course.id)
      end

      def link(slug, section: bridge.name, **extra)
        input(slug, source: "bridge", source_section: section, **extra)
      end

      it "requires the link's required fields once the link is on the form, except the reference back" do
        page = form(linked_course, [input("title"), link("student")], visibility: "member")

        expect(checks(page).required_field_errors).to eq([
          message(:required_link_field_missing, field: "Status", target: "学生", audience: audience("admin")),
          message(:required_link_field_missing, field: "Grade", target: "学生", audience: audience("admin")),
          message(:required_link_field_missing, field: "Status", target: "学生", audience: audience("member"))
        ])
      end

      it "matches a link section by the link entity's id" do
        section = bridge.id.to_s
        page = form(linked_course, [link("student", section: section), link("status", section: section), link("grade", section: section)])

        expect(checks(page).required_field_errors).to eq([])
      end

      it "skips a link with no field on the form" do
        expect(checks(form(linked_course, [input("title")])).required_field_errors).to eq([])
      end
    end
  end

  describe "#submission_process_errors" do
    let(:student) { define("Student", [attribute("full_name", "姓名")]) }
    let(:offline) { [message(:submission_process_offline)] }

    def errors_for(flowchart_id)
      checks(form(student, [input("full_name")], flowchart_id: flowchart_id)).submission_process_errors
    end

    it "passes without a submission process, and with a launched one" do
      launched = create(:flowchart, :simple, :launched_status, customer: customer, entity: student)

      expect(checks(form(student, [input("full_name")])).submission_process_errors).to eq([])
      expect(errors_for(launched.id)).to eq([])
    end

    it "blocks a draft, trashed, missing or other tenant's flowchart" do
      draft = create(:flowchart, :simple, customer: customer, entity: student)
      trashed = create(:flowchart, :simple, customer: customer, entity: student)
      trashed.soft_delete
      foreign = create(:flowchart, :simple, :launched_status, customer: other_customer)

      [draft.id, trashed.id, 0, foreign.id].each { |id| expect(errors_for(id)).to eq(offline) }
    end

    it "blocks a customer flowchart bound to another entity, but not a shared one" do
      teacher = define("Teacher", [attribute("full_name", "姓名")])
      mismatched = create(:flowchart, :simple, :launched_status, customer: customer, entity: teacher)
      shared = create(:flowchart, :shared_type, :simple, :launched_status)

      expect(errors_for(mismatched.id)).to eq(offline)
      expect(errors_for(shared.id)).to eq([])
    end
  end

  it "never names the flowchart in a tenant-facing launch message" do
    keys = %w[reference_label_hidden reference_target_inactive required_field_missing required_link_field_missing submission_process_offline]
    %i[en zh-CN].product(keys).each do |locale, key|
      expect(I18n.t("maint_core.errors.page_launch.#{key}", locale: locale)).not_to match(/flowchart|流程图/i)
    end
  end

  describe "on Page" do
    let(:student) { define("Student", [attribute("full_name", "姓名", validators: required), attribute("motto", "Motto")]) }

    it "adds the checks to launch_errors and refuses to launch" do
      page = form(student, [input("motto")], flowchart_id: 0)
      blockers = [message(:required_field_missing, field: "姓名", audience: audience("admin")), message(:submission_process_offline)]

      expect(page.submission_blockers).to eq(blockers)
      expect(page.launch_errors).to include(*blockers)
      expect { page.launch! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Page.find(page.id).launched).to be(false)
    end

    it "is out of date only when built from a version other than the tenant's head" do
      page = form(student, [input("full_name"), input("motto")])
      expect(page.entity_out_of_date?).to be(false)

      page.update_column(:entity_version_id, student.current_version_id)
      expect(Page.find(page.id).entity_out_of_date?).to be(false)

      student.property_schema_json = student.property_schema_json + [attribute("email", "Email")]
      student.save!(validate: false)
      expect(Page.find(page.id).entity_out_of_date?).to be(true)
    end
  end
end
```

- [ ] **Step 3: Run it to see it fail**

Run: `TEST_ENV_NUMBER=62 bundle exec rspec spec/services/pages/launch_checks_spec.rb`
Expected: FAIL with `uninitialized constant Pages::LaunchChecks`.

- [ ] **Step 4: `Pages::SubmissionProcess`**

Create `app/services/pages/submission_process.rb`:

```ruby
# frozen_string_literal: true

module Pages
  # Resolves the flowchart that runs a page's submissions. The public submit
  # path and the launch checks both resolve it here, so a form launches only
  # when its submissions can run: the flowchart is launched and accessible to
  # the current tenant, and a customer-specific flowchart is bound to the
  # page's entity.
  module SubmissionProcess
    module_function

    def flowchart_id(page)
      page.configuration_json&.dig("form_settings", "flowchart_id")
    end

    def find(id)
      return if id.blank?

      Flowchart.accessible.launched.find_by(id: id)
    end

    def flowchart_for(page)
      find(flowchart_id(page))
    end

    def entity_mismatch?(flowchart, entity)
      return false unless flowchart&.customer_owned?
      return false unless entity && flowchart.entity

      entity.id != flowchart.entity.id
    end

    # True when the page names a flowchart that can't run its submissions.
    def offline?(page, entity:, flowchart: flowchart_for(page))
      return false if flowchart_id(page).blank?

      flowchart.nil? || entity_mismatch?(flowchart, entity)
    end
  end
end
```

- [ ] **Step 5: Use it from `Pages::PublicSubmission`**

In `app/services/pages/public_submission.rb`:

- Replace `flowchart_bound?`'s body with `SubmissionProcess.flowchart_id(@page).present?`.
- Delete the private `flowchart_id` method; its only callers are `flowchart_bound?` and the `find_by` line, both replaced here.
- In `bind_flowchart_and_entity!`, replace the comment and the `Flowchart.accessible.launched.find_by(...)` line with `record = SubmissionProcess.flowchart_for(@page)`.
- Replace `entity_mismatch?`'s body with `SubmissionProcess.entity_mismatch?(@flowchart, @entity)`. Keep its comment.

`RuntimeFlowchart` delegates `customer_owned?` and `entity` to the record, so the mismatch rule reads the same values as before.

- [ ] **Step 6: `Pages::LaunchChecks`**

Create `app/services/pages/launch_checks.rb`:

```ruby
# frozen_string_literal: true

module Pages
  # Launch checks that read beyond the page's own configuration: dropdowns
  # that would list nothing, required attributes missing from the form, and a
  # submission process that is offline. Fields are read through
  # Page#input_fields, so fields inside columns count. Tenant admins read
  # these messages, so none of them names the flowchart.
  class LaunchChecks
    PRIMARY_EXCLUDED_SOURCES = %w[base_model bridge].freeze
    DERIVED_TYPES = %w[Calculated Computed].freeze

    # Memoises what the checks read, so checking many pages costs one read
    # per distinct entity, flowchart and dropdown rather than one per page.
    class Lookup
      ID = /\A\d+\z/

      attr_reader :customer_id

      def initialize(customer_id)
        @customer_id = customer_id
        @entities = {}
        @current_versions = {}
        @flowcharts = {}
        @options = {}
      end

      # The page's entity under Page#entity's tenant rule.
      def entity_for(page)
        entity = entity(page.entity_id)
        return unless entity
        return entity if entity.shared?

        entity if !page.shared? && entity.customer_id == page.customer_id
      end

      # A shared entity or one of this tenant's own.
      def accessible_entity(id)
        entity = entity(id)
        entity if entity && (entity.shared? || entity.customer_id.to_s == customer_id.to_s)
      end

      def current_version(entity)
        @current_versions.fetch(entity.id) do
          @current_versions[entity.id] = entity.resolved_current_version(customer_id)
        end
      end

      def flowchart(id)
        key = id.to_s
        @flowcharts.fetch(key) { @flowcharts[key] = SubmissionProcess.find(id) }
      end

      def reference_options(config, audience)
        key = [config["entity_id"].to_s, config["label_field"].to_s, audience.to_s]
        @options.fetch(key) do
          @options[key] = ::Entities::ReferenceOptions.new(
            entity_id: config["entity_id"], label_field: config["label_field"],
            customer_id: customer_id, audience: audience
          )
        end
      end

      private

      def entity(id)
        key = id.to_s
        return unless key.match?(ID)

        @entities.fetch(key) { @entities[key] = Entity.find_by(id: key) }
      end
    end

    def initialize(page, lookup: Lookup.new(page.customer_id || Current.customer_id))
      @page = page
      @lookup = lookup
    end

    # A dropdown whose target is gone lists nothing for anyone; one whose
    # display field an audience can't see lists nothing for that audience.
    def reference_errors(audiences = @page.visible_audiences)
      return [] if audiences.empty?

      reference_fields.flat_map do |field|
        config = field["dynamic_options"]
        next [message(:reference_target_inactive, field: field_label(field))] unless reference_target(config)

        audiences.filter_map do |audience|
          next if @lookup.reference_options(config, audience).usable?

          message(:reference_label_hidden, field: field_label(field), label: display_field_name(config),
                                           audience: audience_name(audience))
        end
      end
    end

    # Every attribute the contract requires for an audience must have a field,
    # on the entity itself and on each link the form collects.
    def required_field_errors(audiences = @page.visible_audiences)
      entity = @lookup.entity_for(@page)
      return [] unless entity

      own_field_errors(entity, audiences) + link_field_errors(entity, audiences)
    end

    def submission_process_errors
      flowchart = @lookup.flowchart(SubmissionProcess.flowchart_id(@page))
      return [] unless SubmissionProcess.offline?(@page, entity: @lookup.entity_for(@page), flowchart: flowchart)

      [message(:submission_process_offline)]
    end

    # Problems that make every submission of the form fail.
    def submission_blockers
      required_field_errors + submission_process_errors
    end

    private

    def reference_fields
      @page.input_fields.select do |field|
        field["dynamic_options"].is_a?(Hash) && field["dynamic_options"]["options_source"] == "entity_entries"
      end
    end

    def reference_target(config)
      @lookup.reference_options(config, EntityAttributeAudience::ADMIN).target
    end

    def display_field_name(config)
      slug = config["label_field"].to_s
      attribute = Array(reference_target(config)&.property_schema_json).grep(Hash).find { |attr| attr["name_slug"].to_s == slug }
      attribute&.dig("name").presence || slug
    end

    def own_field_errors(entity, audiences)
      present = slugs(@page.input_fields.reject { |field| PRIMARY_EXCLUDED_SOURCES.include?(field["source"].to_s) })
      missing_required(entity, audiences, present) do |attribute, audience|
        message(:required_field_missing, field: attribute_name(attribute), audience: audience_name(audience))
      end
    end

    def link_field_errors(entity, audiences)
      Array(entity.associations_json).grep(Hash).flat_map do |association|
        bridge = @lookup.accessible_entity(association["bridge_entity_id"])
        next [] unless bridge

        present = slugs(link_fields(bridge))
        next [] if present.empty?

        target = link_target_name(association)
        missing_required(bridge, audiences, present, skip: ->(attribute) { back_reference?(attribute, entity) }) do |attribute, audience|
          message(:required_link_field_missing, field: attribute_name(attribute), target: target, audience: audience_name(audience))
        end
      end
    end

    def missing_required(entity, audiences, present, skip: ->(_attribute) { false })
      attributes = Array(entity.property_schema_json).grep(Hash)
      audiences.flat_map do |audience|
        attributes.filter_map do |attribute|
          next unless required_for?(attribute, audience)
          next if skip.call(attribute) || present.include?(attribute["name_slug"].to_s)

          yield attribute, audience
        end
      end
    end

    # The contract's rule: a presence or acceptance validator that applies to
    # the audience. Defaults don't count, because submissions don't apply them.
    def required_for?(attribute, audience)
      return false if attribute["name_slug"].blank? || derived?(attribute)

      requiring = Array(attribute["validators"]).any? do |validator|
        validator.is_a?(Hash) && ValidatorRegistry::REQUIRING_VALIDATIONS.include?(validator["type"].to_s.to_sym)
      end
      requiring && EntityAttributeAudience.applying_audiences(attribute).include?(audience)
    end

    def derived?(attribute)
      DERIVED_TYPES.include?(attribute["type"]) || attribute["storage"] == "computed"
    end

    def link_fields(bridge)
      sections = [bridge.id.to_s, bridge.name.to_s]
      @page.input_fields.select { |field| field["source"] == "bridge" && sections.include?(field["source_section"].to_s) }
    end

    # Pages::BridgeEntries fills in the link's reference to the new entry.
    def back_reference?(attribute, entity)
      attribute["type"] == Entity::ENTITY_REFERENCE_TYPE && attribute["entity_id"].to_s == entity.id.to_s
    end

    def link_target_name(association)
      @lookup.accessible_entity(association["target_entity_id"])&.display_label.presence ||
        association["target_entity_name"].to_s
    end

    def slugs(fields)
      fields.map { |field| field["property_slug"].to_s }.to_set
    end

    def field_label(field)
      field["label"].presence || field["property_slug"].to_s
    end

    def attribute_name(attribute)
      attribute["name"].presence || attribute["name_slug"].to_s
    end

    def audience_name(audience)
      I18n.t("common.visibility.#{audience}")
    end

    def message(key, **vars)
      I18n.t("maint_core.errors.page_launch.#{key}", **vars)
    end
  end
end
```

The entity's `property_schema_json` and `associations_json` come from `Entity#reload_definition_from_head!`, which reads the head for `Current.customer`. That is the definition the tenant's submissions are validated against.

- [ ] **Step 7: Add the checks to launch, and `submission_blockers`**

In `app/models/concerns/page_launch_lifecycle.rb`:

- In the header list, after `#launch_errors`, add:
  - `#   #submission_blockers      — problems that make every submission fail (badges)`
- Replace `launch_errors` with:

```ruby
  # Collect all blocking messages that would prevent a launch.
  def launch_errors
    msgs = []
    msgs << I18n.t("maint_core.errors.page_launch.entity_missing") unless entity&.active?
    msgs << I18n.t("maint_core.errors.page_launch.no_fields") if fields.empty?
    msgs.concat(orphan_rule_errors)
    msgs.concat(orphan_calculation_errors)
    checks = Pages::LaunchChecks.new(self)
    msgs.concat(checks.reference_errors)
    msgs.concat(checks.submission_blockers)
    msgs
  end

  # Required fields missing from the form, or a submission process that is
  # offline. A list of forms passes one lookup so each record is read once.
  def submission_blockers(lookup: nil)
    Pages::LaunchChecks.new(self, **{ lookup: lookup }.compact).submission_blockers
  end
```

- [ ] **Step 8: `entity_out_of_date?`**

In `app/models/concerns/page_entity_binding.rb`:

- Add `#   #entity_out_of_date? — built from an entity version other than the tenant's head` to the header list.
- Add this public method after `entity_id=`:

```ruby
  # True when the page was generated from an entity version other than the
  # head the current tenant sees. Hand-built pages carry no entity_version_id
  # and are never out of date.
  def entity_out_of_date?(current_version = entity&.resolved_current_version)
    entity_version_id.present? && current_version.present? && entity_version_id != current_version.id
  end
```

- [ ] **Step 9: Run the specs**

Run:

```bash
TEST_ENV_NUMBER=62 bundle exec rspec spec/services/pages/launch_checks_spec.rb spec/services/pages/public_submission_spec.rb spec/services/pages/runtime_flowchart_spec.rb spec/models/page_spec.rb spec/requests/admin/maintenance/page_launches_spec.rb spec/requests/public_pages_submission_spec.rb spec/requests/public_pages_tenant_audience_spec.rb
```

Expected: all pass. If an existing page or page-launch example fails because its fixture page names a draft flowchart or omits a required field, don't edit it. List it in your report for T9.

- [ ] **Step 10: Leave the changes uncommitted**

Run: `git add -N app/services/pages/submission_process.rb app/services/pages/launch_checks.rb spec/services/pages/launch_checks_spec.rb && git status --short`
Do not commit.

---

### Task 3: Bindings, trash cascade, flowchart guard

**Agent:** anysys-backend-developer

**Files:**
- Modify: `app/models/page.rb` (scopes)
- Modify: `app/models/concerns/bridge_entity_management.rb` (`soft_delete`)
- Modify: `app/models/flowchart.rb` (`soft_delete`)
- Create: `spec/models/page_bindings_spec.rb`, `spec/models/concerns/entity_trash_cascade_spec.rb`, `spec/models/flowchart_trash_guard_spec.rb`

**Interfaces:**
- Consumes: the T1 keys, and Plan 1 T10's reference guard in `soft_delete`.
- Produces:
  - `Page.for_entity(id)`, which now matches ids stored as numbers or strings.
  - `Page.bound_to_flowchart(flowchart_id)`.
  - `Entity#forms_taken_offline` (Integer).
  - `Flowchart#soft_delete`, which returns false with `errors[:base]` while launched forms use the flowchart.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=63 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing specs**

Create `spec/models/page_bindings_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page, "entity and flowchart bindings" do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  def rewrite(page)
    config = page.configuration_json.deep_dup
    yield config
    page.configuration = config.to_json
    page.save!(validate: false)
    page
  end

  def bind(page, flowchart_id)
    rewrite(page) { |config| config["form_settings"] = { "flowchart_id" => flowchart_id } }
  end

  describe ".for_entity" do
    it "matches a binding stored as a JSON number or as a string" do
      entity = create(:entity, customer: customer)
      number = create(:page, customer: customer, entity: entity)
      text = rewrite(create(:page, customer: customer, entity: entity)) { |config| config["metadata"]["entity_id"] = entity.id.to_s }
      create(:page, customer: customer)

      expect(described_class.for_entity(entity.id)).to contain_exactly(number, text)
      expect(described_class.for_entity(entity.id.to_s)).to contain_exactly(number, text)
    end
  end

  describe ".bound_to_flowchart" do
    it "matches ids stored as numbers and as strings" do
      flowchart = create(:flowchart, :simple, customer: customer)
      number = bind(create(:page, customer: customer), flowchart.id)
      text = bind(create(:page, customer: customer), flowchart.id.to_s)
      bind(create(:page, customer: customer), flowchart.id + 1000)

      expect(described_class.bound_to_flowchart(flowchart.id)).to contain_exactly(number, text)
    end

    it "finds a shared page through a tenant's override head" do
      flowchart = create(:flowchart, :shared_type, :simple)
      shared = Current.set(shared_resources_mode: true) { create(:page, :shared) }
      Current.set(customer: customer) { bind(described_class.find(shared.id), flowchart.id) }

      expect(described_class.find(shared.id).configuration_json["form_settings"]).to be_blank
      expect(described_class.bound_to_flowchart(flowchart.id)).to contain_exactly(shared)
    end

    it "covers every tenant for a shared flowchart and only the owner for a customer flowchart" do
      shared_flowchart = create(:flowchart, :shared_type, :simple)
      own_flowchart = create(:flowchart, :simple, customer: customer)
      mine = bind(create(:page, customer: customer), shared_flowchart.id)
      theirs = bind(create(:page, customer: other_customer), shared_flowchart.id)
      bind(create(:page, customer: other_customer), own_flowchart.id)
      own = bind(create(:page, customer: customer), own_flowchart.id)

      expect(described_class.bound_to_flowchart(shared_flowchart.id)).to contain_exactly(mine, theirs)
      expect(described_class.bound_to_flowchart(own_flowchart.id)).to contain_exactly(own)
    end
  end
end
```

Create `spec/models/concerns/entity_trash_cascade_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entity, "trash cascade to forms" do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  it "takes every launched form bound to the entity offline and counts them" do
    entity = create(:entity, customer: customer, name: "Timesheet")
    live = create(:page, customer: customer, entity: entity, launched: true)
    draft = create(:page, customer: customer, entity: entity, launched: false)
    unrelated = create(:page, customer: customer, launched: true)

    expect(entity.soft_delete).to be_truthy
    expect(entity.forms_taken_offline).to eq(1)
    expect([live, draft, unrelated].map { |page| page.reload.launched }).to eq([false, false, true])
  end

  it "covers every tenant's forms for a shared entity" do
    shared = Current.set(shared_resources_mode: true) { create(:entity, :shared, name: "Campus") }
    mine = create(:page, customer: customer, entity: shared, launched: true)
    theirs = create(:page, customer: other_customer, entity: shared, launched: true)

    trashed = Current.set(shared_resources_mode: true) { described_class.find(shared.id).tap(&:soft_delete) }

    expect(trashed.forms_taken_offline).to eq(2)
    expect([mine, theirs].map { |page| page.reload.launched }).to eq([false, false])
  end

  it "takes a shared form offline while its shared entity is still active" do
    shared, form = Current.set(shared_resources_mode: true) do
      entity = create(:entity, :shared)
      [entity, create(:page, :shared, entity: entity, launched: true)]
    end

    Current.set(shared_resources_mode: true) { expect(described_class.find(shared.id).soft_delete).to be_truthy }
    expect(form.reload.launched).to be(false)
  end

  it "rolls the trash back when a form can't be taken offline" do
    entity = create(:entity, customer: customer)
    form = create(:page, customer: customer, entity: entity, launched: true)
    locked = Page.new.tap { |record| record.errors.add(:base, "Form is locked") }
    allow_any_instance_of(Page).to receive(:take_offline!).and_raise(ActiveRecord::RecordInvalid.new(locked))

    expect(entity.soft_delete).to be(false)
    expect(entity.errors[:base]).to include("Form is locked")
    expect(entity.forms_taken_offline).to eq(0)
    expect(described_class.find(entity.id)).to be_active
    expect(form.reload.launched).to be(true)
  end
end
```

Create `spec/models/flowchart_trash_guard_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flowchart, "#soft_delete while launched forms use it" do
  let_it_be(:customer) { create(:customer) }

  def form_using(flowchart, name:, launched: true)
    page = create(:page, customer: customer, name: name, launched: launched)
    page.configuration = page.configuration_json.merge("form_settings" => { "flowchart_id" => flowchart.id }).to_json
    page.save!(validate: false)
    page
  end

  it "refuses whether the flowchart is a draft or launched, and names the launched forms" do
    [create(:flowchart, :simple, customer: customer), create(:flowchart, :simple, :launched_status, customer: customer)].each do |flowchart|
      form_using(flowchart, name: "Enrol")
      form_using(flowchart, name: "Apply")
      form_using(flowchart, name: "Old", launched: false)

      expect(flowchart.soft_delete).to be(false)
      expect(flowchart.errors[:base]).to eq([
        I18n.t("maint_core.errors.validations.flowchart_in_use", names: %w[Apply Enrol].to_sentence)
      ])
      expect(described_class.find(flowchart.id)).not_to be_deleted
    end
  end

  it "refuses through a tenant's override of a shared form" do
    flowchart = create(:flowchart, :shared_type, :simple)
    shared = Current.set(shared_resources_mode: true) { create(:page, :shared, name: "Shared intake", launched: true) }
    Current.set(customer: customer) do
      page = Page.find(shared.id)
      page.configuration = page.configuration_json.merge("form_settings" => { "flowchart_id" => flowchart.id }).to_json
      page.save!(validate: false)
    end

    expect(flowchart.soft_delete).to be(false)
  end

  it "trashes once no launched form uses it" do
    flowchart = create(:flowchart, :simple, customer: customer)
    form_using(flowchart, name: "Old", launched: false)

    expect(flowchart.soft_delete).to be_truthy
  end
end
```

- [ ] **Step 3: Run them to see them fail**

Run: `TEST_ENV_NUMBER=63 bundle exec rspec spec/models/page_bindings_spec.rb spec/models/concerns/entity_trash_cascade_spec.rb spec/models/flowchart_trash_guard_spec.rb`
Expected: failures that include `undefined method 'bound_to_flowchart'` and `undefined method 'forms_taken_offline'`.

- [ ] **Step 4: Page scopes**

In `app/models/page.rb`, replace the `for_entity` scope and add `bound_to_flowchart` after it:

```ruby
  # Compared as text, so a binding stored as a JSON number or string matches.
  scope :for_entity, ->(entity_id) {
    return none if entity_id.blank?
    joins(current_version: :content).where("CAST(#{CONFIG_ENTITY_ID_SQL} AS TEXT) = ?", entity_id.to_s)
  }
  CONFIG_FLOWCHART_ID_SQL = "CAST(json_extract(page_configuration_contents.payload, '$.form_settings.flowchart_id') AS TEXT)"
  # Pages whose global head or any tenant's override head names the flowchart.
  # A customer-owned flowchart reaches only shared pages and its own tenant's.
  scope :bound_to_flowchart, ->(flowchart_id) {
    return none if flowchart_id.blank?

    versions = PageVersion.joins(:content).where("#{CONFIG_FLOWCHART_ID_SQL} = ?", flowchart_id.to_s).select(:id)
    owner_id = Flowchart.unscoped.where(id: flowchart_id).pick(:customer_id)
    heads = PageCustomerHead.where(current_version_id: versions)
    heads = heads.where(customer_id: owner_id) if owner_id
    bound = where(current_version_id: versions).or(where(id: heads.select(:page_id)))
    owner_id ? bound.where(customer_id: [owner_id, nil]) : bound
  }
```

- [ ] **Step 5: Trash cascade**

In `app/models/concerns/bridge_entity_management.rb`:

- Replace the transaction part of `soft_delete` (from `deleted = false` to the end of the method) with:

```ruby
    @forms_taken_offline = 0
    deleted = false
    self.class.transaction(requires_new: true) do
      raise ActiveRecord::Rollback unless delete_bridge_entities!
      # Before the status change: a shared form's validation looks this entity
      # up through Entity.shared, which hides a trashed entity.
      raise ActiveRecord::Rollback unless take_bound_forms_offline!
      raise ActiveRecord::Rollback unless super

      deleted = true
    end
    @forms_taken_offline = 0 unless deleted
    deleted
  end

  # Launched forms bound to this entity that the last successful trash took
  # offline. A shared entity's count covers every tenant's forms.
  def forms_taken_offline
    @forms_taken_offline.to_i
  end
```

- Add this public method right after `delete_bridge_entities!` (above `private`):

```ruby
  # Takes every launched form bound to this entity offline, in every tenant.
  # Returns false, with the form's errors on this entity, if one can't be.
  def take_bound_forms_offline!
    return true if bridge_entity?

    forms = Page.for_entity(id).launched.to_a
    forms.each(&:take_offline!)
    @forms_taken_offline = forms.size
    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.to_sentence)
    false
  end
```

- [ ] **Step 6: Flowchart trash guard**

In `app/models/flowchart.rb`, add after `launched_edit_locked?` and before `private`:

```ruby
  # Launched forms submit through this flowchart, whether it is launched or a
  # draft that will be relaunched; trashing it would strand them.
  def soft_delete
    names = Page.bound_to_flowchart(id).launched.by_name.pluck(:name)
    if names.any?
      errors.add(:base, I18n.t("maint_core.errors.validations.flowchart_in_use", names: names.to_sentence))
      return false
    end

    super
  end
```

- [ ] **Step 7: Run the specs**

Run:

```bash
TEST_ENV_NUMBER=63 bundle exec rspec spec/models/page_bindings_spec.rb spec/models/concerns/entity_trash_cascade_spec.rb spec/models/flowchart_trash_guard_spec.rb spec/models/page_spec.rb spec/models/page_entity_grouping_spec.rb spec/models/flowchart_spec.rb spec/models/entity_spec.rb spec/models/concerns spec/services/entities/reference_dependents_spec.rb
```

Expected: all pass. A failure in an existing flowchart or entity spec because a fixture form now blocks trash belongs in your report for T9.

- [ ] **Step 8: Leave the changes uncommitted**

Run: `git add -N spec/models/page_bindings_spec.rb spec/models/concerns/entity_trash_cascade_spec.rb spec/models/flowchart_trash_guard_spec.rb && git status --short`
Do not commit.

---

### Task 4: Generator

**Agent:** anysys-backend-developer

**Files:**
- Modify: `app/services/entity_field_organizer.rb`
- Modify: `app/services/page_field_populator.rb` (help text, link section label, readonly branch; not the `dynamic_options` line)
- Modify: `app/services/page_template_applier/field_grouper.rb`
- Modify: `app/services/page_template_applier/layout_element_builder.rb`
- Modify: `spec/services/entity_field_organizer_spec.rb`, `spec/services/page_field_populator_spec.rb`, `spec/services/page_field_populator_calculated_spec.rb`, `spec/services/page_template_applier_spec.rb`

**Interfaces:**
- Consumes: the T1 `maint_core.pages.generator.*` keys.
- Produces:
  - `EntityFieldOrganizer` without derived fields.
  - `help_text` taken from `description`.
  - `source_section_label` set to the related entity's display label.
  - Translated headings, and link sections in attribute-groups mode.
  - `LayoutElementBuilder.element_defaults` raising `ArgumentError`.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=64 bin/rails db:schema:load`

- [ ] **Step 2: Update and add the failing specs**

In `spec/services/page_field_populator_spec.rb`, replace the whole `context "with Calculated and Computed fields"` block with:

```ruby
    context "with Calculated and Computed fields" do
      let(:entity) do
        e = create(:entity, name: "Invoice", customer: customer)
        e.property_schema_json = [
          { "name" => "Price", "name_slug" => "price", "html_type" => "number", "type" => "Float",
            "description" => "Unit price before tax" },
          { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
            "formula" => "price * 2" },
          { "name" => "Average Score", "name_slug" => "average_score", "type" => "Computed",
            "html_type" => "number" }
        ]
        e.save(validate: false)
        e
      end

      it "leaves derived fields out and copies the description into the help text" do
        fields = described_class.call(entity).first["fields"]

        expect(fields.map { |f| f["property_slug"] }).to eq(["price"])
        expect(fields.first["help_text"]).to eq("Unit price before tax")
        expect(fields.first).not_to have_key("readonly")
      end
    end

    context "with a link entity" do
      it "labels link fields with the related entity's display label" do
        student = create(:entity, customer: customer, name: "Student", display_label: "学生",
                                  property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
        course = create(:entity, customer: customer, name: "Course",
                                 property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
        bridge = create(:entity, customer: customer, name: "assoc_course_student", category: :bridge, property_schema: [
          { "name" => "Course", "name_slug" => "course", "type" => "EntityReference", "entity_id" => course.id },
          { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student.id },
          { "name" => "Enrolled on", "name_slug" => "enrolled_on", "html_type" => "date" },
          { "name" => "Days", "name_slug" => "days", "type" => "Calculated", "html_type" => "number", "formula" => "1 + 1" }
        ].to_json)
        allow(course).to receive(:associations_json).and_return([{ "target_entity_id" => student.id, "bridge_entity_id" => bridge.id }])

        link_fields = described_class.call(course).second["fields"]

        expect(link_fields.map { |f| f["property_slug"] }).to eq(%w[student enrolled_on])
        expect(link_fields.map { |f| f["source_section"] }.uniq).to eq(["assoc_course_student"])
        expect(link_fields.map { |f| f["source_section_label"] }.uniq).to eq(["学生"])
      end
    end
```

Replace the two examples in `spec/services/page_field_populator_calculated_spec.rb` with:

```ruby
  it "leaves calculated fields out of generated forms" do
    fields = described_class.call(entity).flat_map { |p| p["fields"] }

    expect(fields.map { |f| f["property_slug"] }).to eq(["price"])
  end

  it "keeps regular fields editable" do
    price_field = described_class.call(entity).flat_map { |p| p["fields"] }.find { |f| f["property_slug"] == "price" }

    expect(price_field["readonly"]).to be_falsey
  end
```

In `spec/services/entity_field_organizer_spec.rb`, add inside the top-level `describe`:

```ruby
  it "leaves calculated and computed attributes out of own fields and grouped fields" do
    customer = create(:customer)
    entity = create(:entity, customer: customer)
    entity.property_schema_json = [
      { "name" => "Price", "name_slug" => "price", "type" => "Float" },
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "formula" => "price * 2" },
      { "name" => "Count", "name_slug" => "count", "type" => "Computed" }
    ]
    entity.save(validate: false)
    entity = Entity.find(entity.id)

    expect(described_class.call(entity)[:own_fields].map { |f| f["name_slug"] }).to eq(["price"])
    expect(described_class.grouped(entity).flat_map { |section| section[:fields] }.map { |f| f["name_slug"] }).to eq(["price"])
  end
```

In `spec/services/page_template_applier_spec.rb`:

- Replace the example `it "titleizes the type as label for unknown element types"` with:

```ruby
      it "raises for unknown element types" do
        fields = [
          { "id" => "f1", "property_slug" => "name", "property_type" => "string",
            "html_type" => "text", "width" => "full", "order" => 0 }
        ]
        expect { described_class.call(fields, "custom_inject_tmpl") }.to raise_error(ArgumentError, /custom_element/)
      end
```

- Inside `context "with group_by: :attribute_groups"`, add:

```ruby
      it "gives each link section its own heading instead of Additional" do
        fields = grouped_fields + [
          { "id" => "l1", "property_slug" => "student", "property_type" => "string", "html_type" => "select",
            "source" => "bridge", "source_section" => "assoc_course_student", "source_section_label" => "Student",
            "group_id" => "g_one", "width" => "full", "order" => 4 }
        ]
        result = described_class.call(fields, "attr_groups_test_tmpl", entity: entity)
        headers = result[:fields].select { |f| f["property_type"] == "layout" && f["field_type"] == "section" }

        expect(headers.map { |h| h["label"] }).to eq(["Account", "Profile", "Additional", "Linked: Student"])
        expect(headers.last["variant"]).to eq("linked")
        expect(result[:fields].last["property_slug"]).to eq("student")
      end

      it "writes zh-CN headings and slugs when generating in zh-CN" do
        fields = grouped_fields + [
          { "id" => "l1", "property_slug" => "student", "property_type" => "string", "html_type" => "select",
            "source" => "bridge", "source_section" => "assoc_course_student", "source_section_label" => "学生",
            "width" => "full", "order" => 4 }
        ]
        result = I18n.with_locale(:"zh-CN") { described_class.call(fields, "attr_groups_test_tmpl", entity: entity) }
        layout = result[:fields].select { |f| f["property_type"] == "layout" }

        expect(layout.select { |f| f["field_type"] == "section" }.map { |h| h["label"] }).to eq(["Account", "Profile", "其他信息", "关联：学生"])
        expect(layout.select { |f| f["field_type"] == "divider" }.map { |d| d["label"] }.uniq).to eq(["分隔线"])
        expect(layout.map { |f| f["property_slug"] }).to all(be_present)
      end
```

- Inside `context "build_source_section_label 'else' branch — unknown source type (line 339)"`, add:

```ruby
      it "translates Other Fields" do
        fields = [{ "id" => "f1", "property_slug" => "x", "property_type" => "string", "html_type" => "text",
                    "source" => "computed", "source_section" => "Derived", "width" => "full", "order" => 0 }]
        result = I18n.with_locale(:"zh-CN") { described_class.call(fields, "other_source_tmpl") }

        expect(result[:fields].select { |f| f["field_type"] == "section" }.map { |h| h["label"] }).to eq(["其他字段"])
      end
```

- [ ] **Step 3: Run them to see them fail**

Run: `TEST_ENV_NUMBER=64 bundle exec rspec spec/services/entity_field_organizer_spec.rb spec/services/page_field_populator_spec.rb spec/services/page_field_populator_calculated_spec.rb spec/services/page_template_applier_spec.rb`
Expected: the new and rewritten examples fail. The rest pass.

- [ ] **Step 4: `EntityFieldOrganizer`**

In `app/services/entity_field_organizer.rb`:

- Under the header's first paragraph, add: `# Calculated and computed attributes are left out: forms never submit them.`
- Add `DERIVED_TYPES = %w[Calculated Computed].freeze` under `EMPTY_SECTIONS`.
- Change `grouped_organized_fields` so each section maps to `{ group: section[:group], fields: section[:attributes].reject { |field| derived?(field) } }`.
- Change `extract_own_fields` to `Array(@entity.property_schema_json).reject { |field| derived?(field) }`.
- Change `extract_bridge_fields`'s reject block to `derived?(f) || (f["type"] == Entity::ENTITY_REFERENCE_TYPE && f["entity_id"].to_s != target_entity_id.to_s)`, with `Array(bridge_entity.property_schema_json)` as the receiver.
- Add the private helper:

```ruby
  def derived?(field)
    field.is_a?(Hash) && DERIVED_TYPES.include?(field["type"])
  end
```

- [ ] **Step 5: `PageFieldPopulator`**

In `app/services/page_field_populator.rb`:

- Change `bridge_label` to `assoc_entity[:entity_display_label] || assoc_entity[:bridge_entity_display_label] || bridge_section`.
- In `build_field`, change `"help_text" => ""` to `"help_text" => prop["description"].to_s`.
- Delete the `# Mark calculated and computed fields as readonly display-only` block (the `if %w[Calculated Computed].include?(prop["type"])` branch). The organizer no longer passes derived fields.
- Leave the `dynamic_options` line exactly as Plan 1 Task 6 left it.

- [ ] **Step 6: `LayoutElementBuilder`**

Replace the class body of `app/services/page_template_applier/layout_element_builder.rb` from `def self.section_header` to the end of `element_defaults` with:

```ruby
    ELEMENT_EXTRAS = {
      "divider" => {},
      "spacer"  => { "spacer_height" => "md" },
      "heading" => { "heading_level" => "h3" }
    }.freeze

    def self.section_header(label, variant: nil)
      header = {
        "id"            => "section_#{SecureRandom.hex(8)}",
        "field_type"    => "section",
        # A translated label such as "关联：学生" parameterizes to "".
        "property_slug" => label.parameterize(separator: "_").presence || "section",
        "property_type" => "layout",
        "label"         => label,
        "content"       => "",
        "placeholder"   => "",
        "help_text"     => "",
        "required"      => false,
        "width"         => "full",
        "order"         => 0
      }
      header["variant"] = variant if variant.present?
      header
    end

    def self.source_section_label(source, source_section)
      case source
      when "base_model" then [source_section.humanize, nil]
      when "entity"     then [source_section, nil]
      when "bridge"     then [I18n.t("maint_core.pages.generator.sections.linked", name: source_section), "linked"]
      else                   [I18n.t("maint_core.pages.generator.sections.other_fields"), nil]
      end
    end

    def self.layout_element(type)
      defaults = element_defaults(type)
      {
        "id"            => "#{type}_#{SecureRandom.hex(8)}",
        "field_type"    => type,
        "property_slug" => "#{type}_#{SecureRandom.hex(4)}",
        "property_type" => "layout",
        "label"         => defaults[:label],
        "content"       => "",
        "placeholder"   => "",
        "help_text"     => "",
        "required"      => false,
        "width"         => "full",
        "order"         => 0
      }.merge(defaults[:extra])
    end

    def self.element_defaults(type)
      extra = ELEMENT_EXTRAS.fetch(type.to_s) { raise ArgumentError, "unknown layout element type: #{type.inspect}" }
      { label: I18n.t("maint_core.pages.generator.layout.#{type}"), extra: extra }
    end
```

Update the class comment's first line to: `# Builds layout-element hashes (section headers, dividers, spacers, headings) with labels translated at generation time.`

- [ ] **Step 7: `FieldGrouper`**

In `app/services/page_template_applier/field_grouper.rb`:

- Replace `reorganize_by_attribute_groups` with:

```ruby
    # Groups the entity's own fields by its curated attribute_groups_json
    # order, with ungrouped ones under a trailing "Additional" section. Link
    # fields always get their own "Linked: <entity>" section after them.
    # Falls back to source-based grouping when @entity is absent or has no
    # named groups.
    def reorganize_by_attribute_groups(working_fields, layout)
      groups = Array(@entity&.attribute_groups_json)
      return reorganize_by_source(working_fields, layout) unless groups.any? { |g| g["name"].to_s.strip != "" }

      entity_fields, link_fields = working_fields[:entity_fields].partition { |field| field["source"].to_s != "bridge" }
      result        = []
      placed_ids    = Set.new

      groups.each do |g|
        name = g["name"].to_s
        next if name.empty?

        members = entity_fields.select { |f| f["group_id"] == g["id"] && !placed_ids.include?(f["id"]) }
        next if members.empty?

        result << @builder.layout_element("divider") if result.any?
        result << @builder.section_header(name)
        members.each { |f| placed_ids << f["id"]; result << f }
      end

      ungrouped = entity_fields.reject { |f| placed_ids.include?(f["id"]) }
      if ungrouped.any?
        result << @builder.layout_element("divider") if result.any?
        result << @builder.section_header(I18n.t("maint_core.pages.generator.sections.additional"))
        result.concat(ungrouped)
      end

      append_link_sections(result, link_fields)
    end
```

- In `reorganize_into_sections`, change `@builder.section_header("Other Fields")` to `@builder.section_header(I18n.t("maint_core.pages.generator.sections.other_fields"))`.
- After `apply_ordering`, add:

```ruby
    private

    def append_link_sections(result, link_fields)
      link_fields.group_by { |field| field["source_section"].to_s }.each_value do |members|
        result << @builder.layout_element("divider") if result.any?
        label, variant = @builder.source_section_label(
          "bridge", members.first["source_section_label"].presence || members.first["source_section"].to_s
        )
        result << @builder.section_header(label, variant: variant)
        result.concat(members)
      end
      result
    end
```

- [ ] **Step 8: Run the specs**

Run:

```bash
TEST_ENV_NUMBER=64 bundle exec rspec spec/services/entity_field_organizer_spec.rb spec/services/page_field_populator_spec.rb spec/services/page_field_populator_calculated_spec.rb spec/services/page_template_applier_spec.rb spec/services/page_template_applier_default_spec.rb spec/services/pages/configuration_composer_spec.rb spec/services/template_preview_builder_spec.rb spec/services/member/surface_template_applier_spec.rb
```

Expected: all pass. A failure elsewhere that asserts on a derived field in a generated form, or on the old link label (the link entity's name), belongs in your report for T9.

- [ ] **Step 9: Leave the changes uncommitted**

Run: `git status --short app/services spec/services`
Do not commit.

---

### Task 5: Hidden sections

**Agent:** anysys-backend-developer

**Files:**
- Modify: `app/services/page_content_generator.rb` (`generate_fields` and new private helpers)
- Modify: `app/services/page_content_generator/layout_elements.rb` (`generate_divider_element`)
- Create: `spec/services/page_content_generator_hidden_sections_spec.rb`

**Interfaces:**
- Consumes: `field_boundary.visible_field?` (existing), the T1 key `maint_core.pages.generator.layout.divider`.
- Produces: per-request removal of sections the viewer can see none of. A divider whose label is the generator default renders without a label.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=65 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing spec**

Create `spec/services/page_content_generator_hidden_sections_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageContentGenerator, "hidden sections" do
  let_it_be(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name_slug" => "name", "name" => "Name" },
      { "name_slug" => "grade", "name" => "Grade", "visibility" => { "public" => false } },
      { "name_slug" => "notes", "name" => "Notes", "visibility" => { "public" => false } }
    ].to_json)
  end

  def render_for(fields)
    config = { "pages" => [{ "id" => "p1", "fields" => fields }] }
    page = double(configuration: config.to_json, configuration_json: config, customer_id: customer.id, entity: entity, id: 7)
    html = Current.set(customer: customer, user: nil) do
      source = described_class.new(page).generate
      ApplicationController.render(inline: source, layout: false, assigns: { page: page, form_action: "/submit" })
    end
    Nokogiri::HTML.fragment(html)
  end

  def section(id, label) = { "id" => id, "field_type" => "section", "property_type" => "layout", "label" => label, "content" => "" }
  def divider(id, label: nil) = { "id" => id, "field_type" => "divider", "property_type" => "layout", "label" => label }
  def paragraph(id, text) = { "id" => id, "field_type" => "paragraph", "property_type" => "layout", "content" => text }
  # No source: the input renders as name="<slug>" while still reading the
  # bound entity's attribute visibility.
  def input(slug) = { "id" => slug, "property_slug" => slug, "html_type" => "text", "label" => slug.titleize }

  it "drops a section whose inputs the viewer can see none of, with its divider and layout elements" do
    doc = render_for([
      section("s_main", "Main"), input("name"),
      divider("d_staff"),
      section("s_staff", "Staff only"), paragraph("p_staff", "Graded by staff"), input("grade"), input("notes")
    ])

    expect(doc.at_css('[data-field-id="s_main"]')).to be_present
    expect(doc.at_css('input[name="name"]')).to be_present
    %w[d_staff s_staff p_staff].each { |id| expect(doc.at_css(%([data-field-id="#{id}"]))).to be_nil }
    expect(doc.text).not_to include("Staff only", "Graded by staff")
  end

  it "counts inputs inside columns as the section's inputs" do
    columns = { "id" => "cols", "field_type" => "columns", "property_type" => "layout",
                "columns" => [{ "fields" => [input("grade")] }, { "fields" => [input("notes")] }] }
    doc = render_for([section("s_main", "Main"), input("name"), section("s_staff", "Staff only"), columns])

    expect(doc.at_css('[data-field-id="s_staff"]')).to be_nil
    expect(doc.at_css('[data-field-id="cols"]')).to be_nil
  end

  it "keeps a content-only section and a section with one visible input" do
    doc = render_for([
      section("s_intro", "Welcome"), paragraph("p_intro", "Please fill in"),
      section("s_mixed", "Mixed"), input("name"), input("grade")
    ])

    expect(doc.at_css('[data-field-id="s_intro"]')).to be_present
    expect(doc.at_css('[data-field-id="s_mixed"]')).to be_present
    expect(doc.at_css('input[name="name"]')).to be_present
    expect(doc.at_css('input[name="grade"]')).to be_nil
  end

  it "renders a generated divider without its default label in any locale" do
    doc = render_for([
      input("name"),
      divider("d_en", label: "Divider"), divider("d_zh", label: "分隔线"), divider("d_named", label: "Contact")
    ])

    expect(doc.text).not_to include("Divider", "分隔线")
    expect(doc.text).to include("Contact")
  end
end
```

- [ ] **Step 3: Run it to see it fail**

Run: `TEST_ENV_NUMBER=65 bundle exec rspec spec/services/page_content_generator_hidden_sections_spec.rb`
Expected: the first two examples and the divider example fail. The content-only example passes.

- [ ] **Step 4: Drop hidden sections in `generate_fields`**

In `app/services/page_content_generator.rb`, replace `generate_fields` with:

```ruby
  def generate_fields(fields)
    fields = without_hidden_sections(fields)
    return "" if fields.empty?
    group_into_rows(fields).map { |row| render_field_row(row) }.join("\n      ")
  end

  # A section whose inputs the viewer can see none of is dropped with its
  # heading, the divider in front of it and its layout elements, so the form
  # shows no empty headings. Sections without inputs render as usual.
  def without_hidden_sections(fields)
    runs = fields.slice_before { |field| layout_type?(field, "section") }.to_a
    hidden = runs.map { |run| hidden_section?(run) }
    runs.each_with_index.flat_map do |run, index|
      next [] if hidden[index]

      hidden[index + 1] && layout_type?(run.last, "divider") ? run[0...-1] : run
    end
  end

  def hidden_section?(run)
    return false unless layout_type?(run.first, "section")

    inputs = run.flat_map { |field| section_inputs(field) }
    inputs.any? && inputs.none? { |field| field_boundary.visible_field?(field) }
  end

  def section_inputs(field)
    return [] unless field.is_a?(Hash)
    return Array(field["columns"]).grep(Hash).flat_map { |column| Array(column["fields"]).flat_map { |nested| section_inputs(nested) } } if field["field_type"] == "columns"

    field["property_type"] == "layout" ? [] : [field]
  end

  def layout_type?(field, type)
    field.is_a?(Hash) && field["property_type"] == "layout" && field["field_type"] == type
  end
```

- [ ] **Step 5: Hide the generator's default divider label**

In `app/services/page_content_generator/layout_elements.rb`, replace `generate_divider_element` with:

```ruby
    def generate_divider_element(field)
      kwargs = { spacing: '"md"' }
      kwargs[:label] = rb_str(field["label"]) if field["label"].present? && !default_divider_label?(field["label"])

      render_component_erb("FormFields::DividerElementComponent", kwargs)
    end

    # The generator writes the divider label in the generating locale; a
    # default label is a placeholder, not text for the form.
    def default_divider_label?(label)
      I18n.available_locales.any? { |locale| I18n.t("maint_core.pages.generator.layout.divider", locale: locale) == label }
    end
```

- [ ] **Step 6: Run the specs**

Run:

```bash
TEST_ENV_NUMBER=65 bundle exec rspec spec/services/page_content_generator_hidden_sections_spec.rb spec/services/page_content_generator_spec.rb spec/services/page_content_generator_runtime_spec.rb spec/services/page_content_generator_safety_spec.rb spec/services/page_content_generator_calculated_spec.rb spec/services/page_content_generator spec/requests/public_pages_visibility_spec.rb spec/requests/public_pages_tenant_audience_spec.rb
```

Expected: all pass.

- [ ] **Step 7: Leave the changes uncommitted**

Run: `git add -N spec/services/page_content_generator_hidden_sections_spec.rb && git status --short`
Do not commit.

---

### Task 6: Audience re-check, form status, assistant

**Agent:** anysys-backend-developer

**Files:**
- Modify: `app/contracts/pages/visibility_contract.rb`
- Create: `app/services/pages/form_health.rb`
- Modify: `spec/contracts/pages/visibility_contract_spec.rb`
- Create: `spec/services/pages/form_health_spec.rb`
- Modify: `spec/services/ai_assistant/assistant/generate_page_spec.rb`

**Interfaces:**
- Consumes: `Pages::LaunchChecks` and its `Lookup`, `Page#submission_blockers(lookup:)` and `Page#entity_out_of_date?` (all T2).
- Produces:
  - `Pages::FormHealth.for(pages, customer_id: Current.customer_id)` returns `{ page_id => Status | nil }`.
  - `Pages::FormHealth::Status = Data.define(:kind, :problems, :built, :current, :entity_name)`, where `kind` is `:cannot_submit` or `:out_of_date`.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=66 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing specs**

Append to `spec/contracts/pages/visibility_contract_spec.rb`, inside the top-level `describe`:

```ruby
  describe "widening a launched form" do
    let(:student) do
      create(:entity, customer: customer, property_schema: [
        { "name" => "姓名", "name_slug" => "full_name", "type" => "String", "html_type" => "text",
          "validators" => [{ "type" => "presence" }], "visibility" => { "public" => false } },
        { "name" => "Email", "name_slug" => "email", "type" => "String", "html_type" => "text",
          "validators" => [{ "type" => "presence" }], "validator_apply" => { "admin" => false } }
      ].to_json)
    end

    def form(launched:, visibility: "admin")
      page = build(:page, customer: customer, entity: student, launched: launched, visibility: visibility,
                          configuration: { "pages" => [{ "id" => "p1", "fields" => [
                            { "id" => "f1", "property_slug" => "full_name", "property_type" => "string", "source" => "entity" }
                          ] }] }.to_json)
      page.save!(validate: false)
      Page.find(page.id)
    end

    around { |example| Current.set(customer: customer) { example.run } }

    it "refuses an audience whose required field isn't on the form" do
      contract = contract_for(form(launched: true))

      expect(contract.validate("visible_audiences" => %w[admin member])).to be(false)
      expect(contract.errors.full_messages).to eq([
        I18n.t("maint_core.errors.page_launch.required_field_missing", field: "Email", audience: I18n.t("common.visibility.member"))
      ])
    end

    it "allows narrowing, and doesn't check an offline form" do
      expect(contract_for(form(launched: true, visibility: "member")).validate("visible_audiences" => ["admin"])).to be(true)
      expect(contract_for(form(launched: false)).validate("visible_audiences" => %w[admin member public])).to be(true)
    end
  end
```

In this fixture, Email's validators don't apply to admins (`validator_apply.admin: false`), so the admin audience passes. Members need Email, and 姓名 is hidden from the public, so it's never required there.

Create `spec/services/pages/form_health_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::FormHealth do
  let_it_be(:customer) { create(:customer) }

  around { |example| Current.set(customer: customer) { example.run } }

  let(:name_attribute) { { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" } }
  let(:student) { create(:entity, customer: customer, name: "Student", property_schema: [name_attribute].to_json) }

  def form(launched:, fields: [{ "id" => "f1", "property_slug" => "name", "property_type" => "string", "source" => "entity" }],
           flowchart_id: nil, built: nil)
    config = { "pages" => [{ "id" => "p1", "fields" => fields }] }
    config["form_settings"] = { "flowchart_id" => flowchart_id } if flowchart_id
    page = build(:page, customer: customer, entity: student, launched: launched, configuration: config.to_json)
    page.save!(validate: false)
    page.update_column(:entity_version_id, built.id) if built
    Page.find(page.id)
  end

  def move_student_forward
    student.property_schema_json = [name_attribute, name_attribute.merge("name" => "Email", "name_slug" => "email")]
    student.save!(validate: false)
  end

  def offline = [I18n.t("maint_core.errors.page_launch.submission_process_offline")]

  it "flags a launched form with blockers ahead of being out of date" do
    page = form(launched: true, flowchart_id: 0, built: student.current_version)
    move_student_forward

    status = described_class.for([page])[page.id]

    expect(status).to have_attributes(kind: :cannot_submit, problems: offline)
  end

  it "flags an out-of-date form, including an offline one with blockers" do
    built = student.current_version
    page = form(launched: false, flowchart_id: 0, built: built)
    move_student_forward
    current = Entity.find(student.id).resolved_current_version

    expect(described_class.for([page])[page.id]).to have_attributes(
      kind: :out_of_date, problems: [], built: built.version_number, current: current.version_number, entity_name: "Student"
    )
  end

  it "needs no badge for a healthy, current or hand-built form" do
    current = form(launched: true, built: student.current_version)
    hand_built = form(launched: true)

    expect(described_class.for([current, hand_built])).to eq(current.id => nil, hand_built.id => nil)
  end

  it "reads each entity and flowchart once for the whole list" do
    pages = Array.new(3) { form(launched: true, flowchart_id: 0, built: student.current_version) }
    count = ->(list) do
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { described_class.for(list) }
      queries
    end

    expect(count.call(pages)).to eq(count.call(pages.first(1)))
  end
end
```

Append to `spec/services/ai_assistant/assistant/generate_page_spec.rb`, inside the top-level `describe`:

```ruby
  it "reports the form as skipped when its submission process is offline" do
    create(:flowchart, :shared_type, :simple, :launched_status,
           name: Pages::Activities::CreateFromEntityVersion::FLOWCHART_NAME)
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    # CreateFromEntityVersion finds its flowchart directly; only the launch
    # check goes through Pages::SubmissionProcess.
    allow(Pages::SubmissionProcess).to receive(:find).and_return(nil)
    result = nil

    expect { result = call_for(entity) }.not_to change(Page, :count)

    expect(result).to have_attributes(ok: false, skipped: :launch_failed, page: nil, created: nil)
    expect(result.message).to include(I18n.t("maint_core.errors.page_launch.submission_process_offline"))
  end
```

- [ ] **Step 3: Run them to see them fail**

Run: `TEST_ENV_NUMBER=66 bundle exec rspec spec/contracts/pages/visibility_contract_spec.rb spec/services/pages/form_health_spec.rb spec/services/ai_assistant/assistant/generate_page_spec.rb`
Expected:
- the "refuses an audience" example fails, because the contract has no check yet;
- the FormHealth spec fails with `uninitialized constant Pages::FormHealth`;
- the GeneratePage example passes already, because T2 added the check. Keep it as the regression.

- [ ] **Step 4: Re-check widened audiences**

In `app/contracts/pages/visibility_contract.rb`:

- Add to the header comment: `# Widening a launched page re-runs the dropdown and required-field launch checks for the audiences it gains (Pages::LaunchChecks); narrowing and offline pages are not checked.`
- After `validates :visibility, ...`, add `validate :launched_audiences_stay_submittable`.
- Add after `deserialize!`:

```ruby
    private

    def launched_audiences_stay_submittable
      return unless model.launched?

      rank = Page::VISIBILITY_LEVELS.index(visibility)
      return unless rank

      added = Page::VISIBILITY_LEVELS.first(rank + 1) - model.visible_audiences
      return if added.empty?

      checks = LaunchChecks.new(model)
      (checks.reference_errors(added) + checks.required_field_errors(added)).each { |message| errors.add(:base, message) }
    end
```

`deserialize!` must stay public. If it sits after the new `private`, move the private block below it.

- [ ] **Step 5: `Pages::FormHealth`**

Create `app/services/pages/form_health.rb`:

```ruby
# frozen_string_literal: true

module Pages
  # The badge each form shows beside its launch status: "Can't be submitted"
  # for a launched form with submission blockers, otherwise "Out of date" for
  # a form generated from an older version of its entity. One lookup serves
  # the whole list, so queries grow with distinct entities and flowcharts,
  # not with rows.
  class FormHealth
    Status = Data.define(:kind, :problems, :built, :current, :entity_name)

    def self.for(pages, customer_id: Current.customer_id)
      new(pages, customer_id: customer_id).statuses
    end

    def initialize(pages, customer_id:)
      @pages = Array(pages)
      @lookup = LaunchChecks::Lookup.new(customer_id)
    end

    # { page id => Status, or nil when the form needs no badge }
    def statuses
      ids = @pages.filter_map(&:entity_version_id)
      built = ids.empty? ? {} : EntityVersion.where(id: ids).index_by(&:id)
      @pages.to_h { |page| [page.id, status_for(page, built[page.entity_version_id])] }
    end

    private

    def status_for(page, built)
      problems = page.launched? ? page.submission_blockers(lookup: @lookup) : []
      return Status.new(kind: :cannot_submit, problems: problems, built: nil, current: nil, entity_name: nil) if problems.any?

      out_of_date(page, built)
    end

    def out_of_date(page, built)
      entity = @lookup.entity_for(page)
      return unless entity && built

      current = @lookup.current_version(entity)
      return unless page.entity_out_of_date?(current)

      Status.new(kind: :out_of_date, problems: [], built: built.version_number, current: current.version_number,
                 entity_name: entity.display_label.presence || entity.name)
    end
  end
end
```

- [ ] **Step 6: Run the specs**

Run:

```bash
TEST_ENV_NUMBER=66 bundle exec rspec spec/contracts/pages/visibility_contract_spec.rb spec/services/pages/form_health_spec.rb spec/services/ai_assistant/assistant/generate_page_spec.rb spec/services/pages/launch_checks_spec.rb
```

Expected: all pass. If the query-count example differs by a constant, print both counts and the extra SQL (`payload[:sql]`) and fix the lookup so the extra page adds no query. Don't loosen the assertion.

- [ ] **Step 7: Leave the changes uncommitted**

Run: `git add -N app/services/pages/form_health.rb spec/services/pages/form_health_spec.rb && git status --short`
Do not commit.

---

### Task 7: Badges

**Agent:** anysys-frontend-developer

**Files:**
- Create: `app/components/admin/pages/form_health_badge_component.rb`
- Modify: `app/components/admin/pages/ops_table_component.rb`, `app/components/admin/pages/ops_table_component.html.erb`
- Modify: `app/views/admin/pages/index.html.erb`, `app/views/admin/maintenance/pages/show.html.erb`
- Create: `spec/components/admin/pages/form_health_badge_component_spec.rb`
- Modify: `spec/components/admin/pages/ops_table_component_spec.rb`

**Interfaces:**
- Consumes: `Pages::FormHealth::Status` (T6), and the `admin_misc.pages.*` keys (T1).
- Produces:
  - `Admin::Pages::FormHealthBadgeComponent.new(status:)`.
  - `Admin::Pages::OpsTableComponent.new(..., statuses: {})`.
  - The views read `@form_statuses` (index) and `@form_status` (show), which T8 sets.

- [ ] **Step 1: Prepare the test database and consult shadcn**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=67 bin/rails db:schema:load`

Open the shadcn `badge` component through the `plugin-shadcn-shadcn` MCP tools (view the component and its examples). Confirm that destructive and warning badges sit inline with status text at the small size. Delivery stays the project's `BadgeComponent` (`variant: :danger` / `:warning`, `size: :sm`), so no new classes are needed.

- [ ] **Step 2: Write the failing specs**

Create `spec/components/admin/pages/form_health_badge_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Pages::FormHealthBadgeComponent, type: :component do
  def status(kind, problems: [], built: nil, current: nil, entity_name: nil)
    Pages::FormHealth::Status.new(kind: kind, problems: problems, built: built, current: current, entity_name: entity_name)
  end

  it "renders nothing for a form that needs no badge" do
    render_inline(described_class.new(status: nil))

    expect(page).not_to have_css(".badge")
  end

  it "flags a form that can't be submitted, with every problem in the tooltip" do
    render_inline(described_class.new(status: status(:cannot_submit, problems: ["Name is missing", "Process offline"])))
    hint = I18n.t("admin_misc.pages.cannot_submit_hint", problems: "Name is missing; Process offline")

    expect(page).to have_css(".badge.badge-danger", text: I18n.t("admin_misc.pages.cannot_submit"))
    expect(page.find(".badge")["data-tooltip"]).to eq(hint)
    expect(page).to have_css(".sr-only", text: hint)
  end

  it "flags an out-of-date form with both version numbers" do
    render_inline(described_class.new(status: status(:out_of_date, built: 1, current: 3, entity_name: "Student")))

    expect(page).to have_css(".badge.badge-warning", text: I18n.t("admin_misc.pages.out_of_date"))
    expect(page.find(".badge")["data-tooltip"]).to eq(
      I18n.t("admin_misc.pages.out_of_date_hint", built: 1, entity: "Student", current: 3)
    )
  end

  it "speaks zh-CN" do
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(status: status(:out_of_date, built: 1, current: 2, entity_name: "学生")))
    end

    expect(page).to have_text("版本过旧")
    expect(page.find(".badge")["data-tooltip"]).to eq("基于第 1 版生成；学生当前为第 2 版。")
  end
end
```

Append to `spec/components/admin/pages/ops_table_component_spec.rb`, inside the top-level `describe`:

```ruby
  it "shows a form's status badge on both the card and the row" do
    status = Pages::FormHealth::Status.new(kind: :cannot_submit, problems: ["Offline"], built: nil, current: nil, entity_name: nil)
    render_table(statuses: { page_live.id => status })

    expect(page).to have_css(".badge-danger", text: I18n.t("admin_misc.pages.cannot_submit"), count: 2)
  end

  it "shows no status badge without statuses" do
    render_table(statuses: nil)

    expect(page).not_to have_css(".badge-danger, .badge-warning")
  end
```

- [ ] **Step 3: Run them to see them fail**

Run: `TEST_ENV_NUMBER=67 bundle exec rspec spec/components/admin/pages/form_health_badge_component_spec.rb spec/components/admin/pages/ops_table_component_spec.rb`
Expected: FAIL with `uninitialized constant Admin::Pages::FormHealthBadgeComponent` and `unknown keyword: :statuses`.

- [ ] **Step 4: The badge component**

Create `app/components/admin/pages/form_health_badge_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Pages
    # "Can't be submitted" or "Out of date" beside a form's launch status,
    # with the reason in the tooltip and for screen readers. Renders nothing
    # for a form that needs no badge.
    class FormHealthBadgeComponent < ApplicationComponent
      VARIANTS = { cannot_submit: :danger, out_of_date: :warning }.freeze

      def initialize(status:)
        @status = status
      end

      def render?
        @status.present? && VARIANTS.key?(@status.kind)
      end

      def call
        render(BadgeComponent.new(variant: VARIANTS.fetch(@status.kind), size: :sm, data: { tooltip: hint })) do
          safe_join([label, tag.span(hint, class: "sr-only")], " ")
        end
      end

      private

      def label
        t("admin_misc.pages.#{@status.kind}")
      end

      def hint
        if @status.kind == :cannot_submit
          t("admin_misc.pages.cannot_submit_hint", problems: @status.problems.join("; "))
        else
          t("admin_misc.pages.out_of_date_hint", built: @status.built, entity: @status.entity_name, current: @status.current)
        end
      end
    end
  end
end
```

`"; "` matches how `Page#launch!` joins its errors.

- [ ] **Step 5: The forms list**

In `app/components/admin/pages/ops_table_component.rb`:

- Add `statuses: {},` to the `initialize` keywords, after `frame_id: FRAME_ID`.
- Set `@statuses = statuses || {}`.
- Add the public reader:

```ruby
      # Badge status for a row (Pages::FormHealth), or nil.
      def form_status(page)
        @statuses[page.id]
      end
```

In `app/components/admin/pages/ops_table_component.html.erb`:

- Mobile card: directly after the status pill's closing `</span>`, and before `AudienceReachComponent`, add:

```erb
              <%= render Admin::Pages::FormHealthBadgeComponent.new(status: form_status(page_row)) %>
```

- Desktop row: inside the name cell's `<div class="min-w-0">`, after the entity-subtitle `<% end %>`, add:

```erb
                    <% if (status = form_status(page_row)) %>
                      <div class="mt-1"><%= render Admin::Pages::FormHealthBadgeComponent.new(status: status) %></div>
                    <% end %>
```

The status column is `w-28`, too narrow for a second badge. The name column takes the remaining width, so the badge goes under the subtitle.

In `app/views/admin/pages/index.html.erb`, add `statuses: @form_statuses,` to the `OpsTableComponent.new(...)` arguments, after `filters: @filters,`.

- [ ] **Step 6: The page header**

In `app/views/admin/maintenance/pages/show.html.erb`, inside `<div class="flex flex-wrap items-center gap-2 mb-6">`, after the launch `BadgeComponent` block, add:

```erb
    <%= render Admin::Pages::FormHealthBadgeComponent.new(status: @form_status) %>
```

- [ ] **Step 7: Run the specs**

Run: `TEST_ENV_NUMBER=67 bundle exec rspec spec/components/admin/pages`
Expected: all pass.

- [ ] **Step 8: Leave the changes uncommitted**

Run: `git add -N app/components/admin/pages/form_health_badge_component.rb spec/components/admin/pages/form_health_badge_component_spec.rb && git status --short`
Do not commit.

---

### Task 8: Controllers

**Agent:** anysys-security-engineer

**Files:**
- Modify:
  - `app/controllers/admin/maintenance/entities_controller.rb` (`destroy`)
  - `app/controllers/admin/maintenance/base_restorations_controller.rb`
  - `app/controllers/admin/maintenance/entity_restorations_controller.rb`
  - `app/controllers/admin/maintenance/flowcharts_controller.rb` (`destroy`)
  - `app/controllers/admin/maintenance/flowchart_launches_controller.rb` (`destroy`)
  - `app/controllers/admin/maintenance/pages_controller.rb` (`show`)
  - `app/controllers/admin/pages_controller.rb` (`index`)
- Modify specs:
  - `spec/requests/admin/maintenance/{entities,entity_restorations,flowcharts,flowchart_launches,pages}_spec.rb`
  - `spec/requests/admin/pages_spec.rb`

**Interfaces:**
- Consumes:
  - `Entity#forms_taken_offline`, `Page.for_entity`, `Page.bound_to_flowchart` and `Flowchart#soft_delete` (T3);
  - `Pages::FormHealth` (T6);
  - the T1 keys;
  - the T7 views, which read `@form_statuses` and `@form_status`.
- Produces: the flash messages, plus `@form_statuses` (index) and `@form_status` (show). No new routes. Every changed action keeps its existing guard: entities and restorations are admin-or-owner, flowcharts and flowchart launches are owner-only, and both page surfaces are admin-or-owner.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=68 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing request specs**

Each block below defines its own `let`s, so it doesn't depend on the host file's names. The exception is the flowcharts block, which reuses the file's sign-in.

Append to `spec/requests/admin/maintenance/entities_spec.rb`:

```ruby
RSpec.describe "Admin::Maintenance::Entities trash cascade", type: :request do
  let(:cascade_customer) { create(:customer) }
  let(:cascade_admin) { create(:user, :admin, customer: cascade_customer) }

  it "takes the entity's live forms offline and says so" do
    sign_in cascade_admin
    entity = create(:entity, customer: cascade_customer, name: "Timesheet")
    form = create(:page, customer: cascade_customer, entity: entity, launched: true)

    delete "/#{cascade_customer.id}/admin/maintenance/entities/#{entity.id}"

    expect(flash[:notice]).to eq(
      "#{I18n.t('maint_core.flash.entities.deleted')} #{I18n.t('maint_core.flash.entities.forms_taken_offline', count: 1)}"
    )
    expect(form.reload.launched).to be(false)
  end

  it "keeps the plain notice when no form was live" do
    sign_in cascade_admin
    entity = create(:entity, customer: cascade_customer)

    delete "/#{cascade_customer.id}/admin/maintenance/entities/#{entity.id}"

    expect(flash[:notice]).to eq(I18n.t("maint_core.flash.entities.deleted"))
  end
end
```

Append to `spec/requests/admin/maintenance/entity_restorations_spec.rb`, inside the top-level `describe` (it defines `customer` and `admin`):

```ruby
  describe "PATCH update — forms left offline" do
    it "names the entity's offline forms" do
      sign_in admin
      entity = create(:entity, customer: customer, name: "Timesheet")
      create(:page, customer: customer, entity: entity, name: "Weekly hours", launched: true)
      entity.soft_delete

      patch "/#{customer.id}/admin/maintenance/entities/#{entity.id}/restoration"

      expect(flash[:notice]).to eq(
        "#{I18n.t('maint_core.flash.entity_restorations.restored', name: 'Timesheet')} " \
        "#{I18n.t('maint_core.flash.entity_restorations.offline_forms', names: 'Weekly hours')}"
      )
    end
  end
```

In `spec/requests/admin/maintenance/flowcharts_spec.rb`, add next to the existing `describe "DELETE destroy"`, in the same group so it inherits that group's sign-in:

```ruby
  describe "DELETE destroy — launched forms use the flowchart" do
    it "keeps the flowchart and shows why" do
      form = create(:page, customer: customer, name: "Apply", launched: true)
      form.configuration = form.configuration_json.merge("form_settings" => { "flowchart_id" => flowchart.id }).to_json
      form.save!(validate: false)

      delete flowchart_path

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq(I18n.t("maint_core.errors.validations.flowchart_in_use", names: "Apply"))
      expect(Flowchart.exists?(flowchart.id)).to be(true)
    end
  end
```

Append to `spec/requests/admin/maintenance/flowchart_launches_spec.rb`, inside the top-level `describe`:

```ruby
  describe "DELETE destroy — launched forms use the flowchart" do
    before { sign_in platform_owner }

    it "reports how many launched forms stop accepting submissions" do
      flowchart.update!(status: :launched)
      form = create(:page, customer: customer, launched: true)
      form.configuration = form.configuration_json.merge("form_settings" => { "flowchart_id" => flowchart.id }).to_json
      form.save!(validate: false)

      delete "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/launch"

      expect(flash[:notice]).to eq(
        "#{I18n.t('maint_core.flash.flowchart_launches.taken_offline')} " \
        "#{I18n.t('maint_core.flash.flowchart_launches.forms_stopped', count: 1)}"
      )
    end
  end
```

Append to `spec/requests/admin/pages_spec.rb`:

```ruby
RSpec.describe "Admin::Pages status badges", type: :request do
  let(:badge_customer) { create(:customer) }
  let(:badge_admin) { create(:user, :admin, customer: badge_customer) }

  it "flags a launched form that can't be submitted" do
    sign_in badge_admin
    entity = create(:entity, customer: badge_customer, property_schema: [
      { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text", "validators" => [{ "type" => "presence" }] }
    ].to_json)
    create(:page, customer: badge_customer, entity: entity, name: "Intake", launched: true)

    get "/#{badge_customer.id}/admin/pages"

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).text).to include(I18n.t("admin_misc.pages.cannot_submit"))
  end
end
```

Append to `spec/requests/admin/maintenance/pages_spec.rb`:

```ruby
RSpec.describe "Admin::Maintenance::Pages out-of-date badge", type: :request do
  let(:badge_customer) { create(:customer) }
  let(:badge_admin) { create(:user, :admin, customer: badge_customer) }

  it "shows Out of date when the entity moved past the form's version" do
    sign_in badge_admin
    name = { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" }
    entity = create(:entity, customer: badge_customer, name: "Student", property_schema: [name].to_json)
    form = create(:page, customer: badge_customer, entity: entity)
    form.update_column(:entity_version_id, entity.current_version_id)
    entity.property_schema_json = [name, name.merge("name" => "Email", "name_slug" => "email")]
    entity.save!(validate: false)

    get "/#{badge_customer.id}/admin/maintenance/pages/#{form.id}"

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).text).to include(I18n.t("admin_misc.pages.out_of_date"))
  end
end
```

- [ ] **Step 3: Run them to see them fail**

Run:

```bash
TEST_ENV_NUMBER=68 bundle exec rspec spec/requests/admin/maintenance/entities_spec.rb spec/requests/admin/maintenance/entity_restorations_spec.rb spec/requests/admin/maintenance/flowcharts_spec.rb spec/requests/admin/maintenance/flowchart_launches_spec.rb spec/requests/admin/maintenance/pages_spec.rb spec/requests/admin/pages_spec.rb
```

Expected: the new examples fail on their flash or badge assertions. The plain-notice example passes.

- [ ] **Step 4: Entities destroy**

In `app/controllers/admin/maintenance/entities_controller.rb`, change the success `format.html` redirect's notice to `notice: destroyed_notice`, and add this private method:

```ruby
    def destroyed_notice
      notices = [t("maint_core.flash.entities.deleted")]
      count = @entity.forms_taken_offline
      notices << t("maint_core.flash.entities.forms_taken_offline", count: count) if count.positive?
      notices.join(" ")
    end
```

- [ ] **Step 5: Restorations**

In `app/controllers/admin/maintenance/base_restorations_controller.rb`, change the success notice to `notice: restored_notice(record)` and add:

```ruby
      private

      # Subclasses may append follow-up guidance to the restored message.
      def restored_notice(record)
        t(restored_flash_key, name: record.name)
      end
```

In `app/controllers/admin/maintenance/entity_restorations_controller.rb`, add after `restorable ...`:

```ruby
      private

      # Forms taken offline when the entity was trashed stay offline.
      def restored_notice(record)
        names = Page.accessible.for_entity(record.id).where(launched: false).by_name.pluck(:name)
        return super if names.empty?

        "#{super} #{t('maint_core.flash.entity_restorations.offline_forms', names: names.to_sentence)}"
      end
```

- [ ] **Step 6: Flowchart destroy and take offline**

In `app/controllers/admin/maintenance/flowcharts_controller.rb`, replace `destroy` with:

```ruby
    def destroy
      if @flowchart.soft_delete
        redirect_to admin_maintenance_flowcharts_path(current_customer_id), notice: t("maint_core.flash.flowcharts.deleted")
      else
        redirect_to admin_maintenance_flowcharts_path(current_customer_id), alert: @flowchart.errors.full_messages.to_sentence
      end
    end
```

In `app/controllers/admin/maintenance/flowchart_launches_controller.rb`, change the `destroy` success redirect's notice to `notice: taken_offline_notice` and add this private method:

```ruby
      # Launched forms bound to the flowchart can't accept submissions until
      # it is launched again.
      def taken_offline_notice
        notice = t("maint_core.flash.flowchart_launches.taken_offline")
        count = Page.bound_to_flowchart(@flowchart.id).launched.count
        count.positive? ? "#{notice} #{t('maint_core.flash.flowchart_launches.forms_stopped', count: count)}" : notice
      end
```

- [ ] **Step 7: Form status on the list and the header**

In `app/controllers/admin/pages_controller.rb`, `index`, add after `@pagination = result[:pagination]`:

```ruby
      @form_statuses = ::Pages::FormHealth.for(@rows)
```

In `app/controllers/admin/maintenance/pages_controller.rb`, `show`, change `format.html` to:

```ruby
        format.html { @form_status = ::Pages::FormHealth.for([@page])[@page.id] }
```

Use `::Pages`, because inside `Admin` the bare name resolves to `Admin::Pages`.

- [ ] **Step 8: Run the specs and the auth audit**

Run the Step 3 command again, plus:

```bash
TEST_ENV_NUMBER=68 bundle exec rspec spec/requests/admin/maintenance/entities_route_audit_spec.rb spec/requests/admin/maintenance/entity_lifecycle_route_audit_spec.rb spec/requests/admin/maintenance/flowchart_restorations_spec.rb spec/requests/admin/pages_route_audit_spec.rb
```

Expected: all pass. Then read `.cursor/skills/audit-auth/SKILL.md` and follow it on the diff of the seven controllers. Report its result.

- [ ] **Step 9: Leave the changes uncommitted**

Run: `git status --short app/controllers spec/requests`
Do not commit.

---

### Task 9: Fixture sweep

**Agent:** anysys-qa-engineer

**Files:**
- Modify: spec files not owned by T2–T8, fixtures only. Never edit production code.

**Interfaces:**
- Consumes: every Plan 3 change, and the failure lists that T2–T5 reported.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=69 bin/rails db:schema:load`

- [ ] **Step 2: Run every area the new checks reach**

Run:

```bash
TEST_ENV_NUMBER=69 bundle exec rspec spec/models spec/contracts spec/services/pages spec/services/ai_assistant spec/services/page_content_generator* spec/services/page_template_applier* spec/services/page_field_populator* spec/services/entity_field_organizer_spec.rb spec/services/template_preview_builder_spec.rb spec/services/member spec/services/flowchart_definitions spec/requests/admin spec/requests/public_pages* spec/requests/member spec/components/admin spec/integration
```

- [ ] **Step 3: Repair fixtures under the stale-test policy**

For each failure, decide whether production intentionally changed:

- A spec that launches a form whose fixture lacks a required field, names a draft or missing flowchart, or binds a customer flowchart to another entity: make the fixture realistic. Add the field, launch the flowchart, or bind it to the right entity. Never remove a launch check.
- A spec that trashes a flowchart or entity while a launched fixture form uses it: take the form offline first, or assert the new refusal or cascade if that is what the example is about.
- A spec that asserts a derived field in a generated form, the link entity's name as a link label, a titleized unknown layout element, or the old flash text: update the expectation to the new behaviour.
- Anything else is a real regression. Stop and report it with the failure output.

- [ ] **Step 4: Re-run until green**

Run the Step 2 command again.
Expected: 0 failures. Paste the summary line, and list every spec file you changed with a one-line reason.

---

### Task 10: Plan 3 docs

**Agent:** anysys-backend-developer

**Files:**
- Modify: `doc/reference/en/page-builder.md`, `doc/reference/zh-CN/page-builder.md`
- Modify: `doc/reference/en/page-rendering.md`, `doc/reference/zh-CN/page-rendering.md`
- Modify: `doc/reference/en/flowchart-builder.md`, `doc/reference/zh-CN/flowchart-builder.md`
- Modify: `doc/reference/en/entity-builder.md`, `doc/reference/zh-CN/entity-builder.md`

Anchors are quoted text, not line numbers, because Plans 1 and 2 also edit these files.

- [ ] **Step 1: `page-builder.md`, Model paragraph and Public submit**

- In the paragraph starting `` `Page#launch!` raises `` (en), replace "and calculation `target_field_id`s must still exist." with "calculation `target_field_id`s must still exist, and the checks under \"Launch checks\" must pass."
- In the zh-CN paragraph starting "`launch_errors` 非空时", replace "计算的 `target_field_id` 也必须仍存在。" with "计算的 `target_field_id` 也必须仍存在，并通过“上线检查”中的各项检查。"
- In **Public submit**, replace "loads `Flowchart.accessible.referenceable`," with "resolves it through `Pages::SubmissionProcess` (`Flowchart.accessible.launched`, the same lookup the launch check uses),".
- In zh-CN **公开提交**, replace "加载 `Flowchart.accessible.referenceable`，" with "通过 `Pages::SubmissionProcess` 解析（`Flowchart.accessible.launched`，与上线检查使用同一查找），".

- [ ] **Step 2: `page-builder.md`, three new subsections**

Insert before `### Assistant-generated forms` (en):

```markdown
### Launch checks

`launch_errors` also runs `Pages::LaunchChecks`. It reads fields through `Page#input_fields` (columns flattened) for every audience in `visible_audiences`, against the tenant's current entity definition:

- **Dropdowns.** An `entity_entries` field blocks launch when its target is missing or trashed (`reference_target_inactive`), or when its display field can't label a choice for an audience (`reference_label_hidden`, which names the audience).
- **Required fields.** Every attribute with a `presence` or `acceptance` validator that applies to an audience (`EntityAttributeAudience.applying_audiences`) needs a field on the form (`required_field_missing`). The entity's own attributes match by `property_slug` on fields whose source is neither `base_model` nor `bridge`. A link entity with at least one field on the form is checked against fields with its `source_section` (the link's id or name), skipping the reference back to the entity (`required_link_field_missing`). Calculated and computed attributes never count, and a default value doesn't satisfy the check, because submissions don't apply defaults.
- **Submission process.** A page with `form_settings.flowchart_id` needs that flowchart to resolve through `Pages::SubmissionProcess`, the lookup `Pages::PublicSubmission` uses (`Flowchart.accessible.launched`, plus the entity-mismatch rule for customer flowcharts). Otherwise launch is blocked with `submission_process_offline`. Tenant admins read these messages, so none of them says "flowchart".

`Page#submission_blockers` is the required-field and submission-process part. Widening a launched page's audiences through `Pages::VisibilityContract` re-runs the dropdown and required-field checks for the added audiences, and refuses the change if either fails. Narrowing, and offline pages, aren't checked. `AiAssistant::Assistant::GeneratePage` reports a generated form that fails these checks as skipped, with the reason.

### Generated layout

`EntityFieldOrganizer` leaves calculated and computed attributes out of generated forms and the builder palette, on the entity and on its links. `PageFieldPopulator` copies an attribute's `description` into `help_text`, and labels each link section with the related entity's display label. `PageTemplateApplier::FieldGrouper` and `LayoutElementBuilder` translate the headings and layout labels they write (`maint_core.pages.generator.*`) at generation time. Link fields always get their own "Linked: <entity>" section, in both the source and attribute-groups modes. `LayoutElementBuilder.element_defaults` raises `ArgumentError` for any type other than `divider`, `spacer` and `heading`.

### Status badges

The forms list (`Admin::Pages::OpsTableComponent`, on the card and the row) and the page header show at most one badge from `Pages::FormHealth`:

- **Can't be submitted** (`variant: :danger`): the page is launched and `submission_blockers` isn't empty. The tooltip lists the blockers.
- **Out of date** (`variant: :warning`): otherwise, when `Page#entity_out_of_date?` is true, meaning `entity_version_id` differs from the entity version the tenant sees. Hand-built pages have no `entity_version_id` and are never out of date.

One `Pages::LaunchChecks::Lookup` serves the whole list, so queries grow with distinct entities and flowcharts, not rows.
```

Insert before `### 助手生成的表单` (zh-CN):

```markdown
### 上线检查

`launch_errors` 还会运行 `Pages::LaunchChecks`。它通过 `Page#input_fields`（分栏展开）读取字段，针对 `visible_audiences` 中的每个受众，按租户当前的实体定义检查：

- **下拉列表。** `entity_entries` 字段的目标实体不存在或已在回收站时，阻止上线（`reference_target_inactive`）；显示字段无法为某个受众作选项标签时，同样阻止上线（`reference_label_hidden`，消息中写明受众）。
- **必填字段。** 带有 `presence` 或 `acceptance` 校验、且该校验适用于某受众（`EntityAttributeAudience.applying_audiences`）的属性，表单上必须有对应字段（`required_field_missing`）。实体自身的属性按 `property_slug` 匹配来源既非 `base_model` 也非 `bridge` 的字段。表单上至少有一个字段的关联实体，按其 `source_section`（关联的 ID 或名称）检查，跳过指回本实体的引用（`required_link_field_missing`）。计算字段和汇总字段不计入；默认值不能满足检查，因为提交不会应用默认值。
- **提交流程。** 设置了 `form_settings.flowchart_id` 的页面，该流程图必须能通过 `Pages::SubmissionProcess` 解析，即 `Pages::PublicSubmission` 使用的查找（`Flowchart.accessible.launched`，客户流程图还需符合实体一致规则）。否则以 `submission_process_offline` 阻止上线。这些消息面向租户管理员，因此都不提“流程图”。

`Page#submission_blockers` 即必填字段与提交流程两部分。通过 `Pages::VisibilityContract` 扩大已上线页面的受众时，会针对新增受众重新运行下拉列表和必填字段检查，任一失败即拒绝修改。缩小受众及未上线页面不做检查。`AiAssistant::Assistant::GeneratePage` 会把未通过这些检查的生成表单报告为已跳过，并附原因。

### 生成的布局

`EntityFieldOrganizer` 在生成的表单和构建器面板中略去计算字段和汇总字段，实体自身和关联实体均如此。`PageFieldPopulator` 把属性的 `description` 复制到 `help_text`，并以关联实体的显示名称标注每个关联分节。`PageTemplateApplier::FieldGrouper` 与 `LayoutElementBuilder` 在生成时翻译所写入的标题和布局标签（`maint_core.pages.generator.*`）。无论按来源还是按属性分组，关联字段始终单独成为“关联：<实体>”分节。`LayoutElementBuilder.element_defaults` 对 `divider`、`spacer`、`heading` 以外的类型抛出 `ArgumentError`。

### 状态标记

表单列表（`Admin::Pages::OpsTableComponent`，卡片和表格行）与页面标题最多显示一个来自 `Pages::FormHealth` 的标记：

- **无法提交**（`variant: :danger`）：页面已上线且 `submission_blockers` 非空，提示中列出阻止原因。
- **版本过旧**（`variant: :warning`）：否则，当 `Page#entity_out_of_date?` 为真，即 `entity_version_id` 与租户当前看到的实体版本不同时显示。手动构建的页面没有 `entity_version_id`，不会标记为版本过旧。

整个列表共用一个 `Pages::LaunchChecks::Lookup`，查询次数随不同实体和流程图的数量增长，而非随行数增长。
```

- [ ] **Step 3: `page-rendering.md`, hidden sections**

After the paragraph starting "An unbound UI preview renders only source-free controls" (en), add:

```markdown
`PageContentGenerator#generate_fields` drops a section the viewer can see none of. Fields split into runs at each `section` element. A run with at least one input field (fields inside columns count) where `Pages::FormParams#visible_field?` is false for all of them is removed, together with its heading, the divider right before it and its layout elements. Runs without input fields render as usual. This happens per request, for the viewer's audience. A divider whose label is the generator default (`maint_core.pages.generator.layout.divider` in any locale) renders without a label.
```

After the paragraph starting "未绑定实体的 UI 预览仅在禁用的 fieldset 内渲染" (zh-CN), add:

```markdown
`PageContentGenerator#generate_fields` 会去掉访问者一个字段都看不到的分节。字段在每个 `section` 元素处切分为若干段；某段至少有一个输入字段（分栏内字段也计入），且 `Pages::FormParams#visible_field?` 对其全部为 false 时，该段连同分节标题、紧挨其前的分隔线及段内布局元素一并移除。没有输入字段的段照常渲染。该处理在每次请求时按访问者受众进行。分隔线标签若为生成器默认值（任一语言下的 `maint_core.pages.generator.layout.divider`），渲染时不显示标签。
```

- [ ] **Step 4: `flowchart-builder.md`, forms that depend on a flowchart**

After the paragraph starting "Launch is `FlowchartLaunchesController#create`" (en), add:

```markdown
Forms depend on launched flowcharts. `Flowchart#soft_delete` refuses while `Page.bound_to_flowchart(id).launched` exists, whether the flowchart is launched or a draft, and lists the forms (`maint_core.errors.validations.flowchart_in_use`). `FlowchartsController#destroy` redirects with that alert. `Page.bound_to_flowchart` compares `form_settings.flowchart_id` as text, through the global head or any tenant's override head. A customer-owned flowchart reaches only shared pages and its own tenant's. Taking a flowchart offline still works, and the notice appends `maint_core.flash.flowchart_launches.forms_stopped` with the number of launched forms that can't accept submissions until it is launched again. Those forms show **Can't be submitted**, and a form can't be launched while its flowchart is offline; see [Page builder](page-builder).
```

After the paragraph starting "发布是 `FlowchartLaunchesController#create`" (zh-CN), add:

```markdown
表单依赖已发布的流程图。只要存在 `Page.bound_to_flowchart(id).launched`，无论流程图已发布还是草稿，`Flowchart#soft_delete` 都会拒绝，并列出这些表单（`maint_core.errors.validations.flowchart_in_use`）；`FlowchartsController#destroy` 以该提示重定向。`Page.bound_to_flowchart` 以文本比较 `form_settings.flowchart_id`，覆盖全局头版本及各租户的覆盖头版本；客户自有流程图只涉及共享页面和该租户自己的页面。流程图仍可下线，提示会追加 `maint_core.flash.flowchart_launches.forms_stopped`，说明在重新发布前无法接收提交的已上线表单数量。这些表单显示“无法提交”，流程图下线期间表单也无法上线；见 [页面构建器](page-builder)。
```

- [ ] **Step 5: `entity-builder.md`, trash cascade**

After the paragraph starting "`template_fields` runs `TemplateFieldExtractor`" (en), add:

```markdown
Trashing an entity also takes its launched forms offline, inside the same transaction and before the status change: `soft_delete` calls `take_offline!` on every `Page.for_entity(id).launched`, which for a shared entity means every tenant's forms. `Page.for_entity` compares the stored binding as text, so a JSON number or string matches. `forms_taken_offline` holds the count, and `destroy` appends `maint_core.flash.entities.forms_taken_offline` to its notice when it is positive. If a form can't be taken offline, the trash rolls back. Restoring doesn't relaunch forms: `EntityRestorationsController#restored_notice` appends `maint_core.flash.entity_restorations.offline_forms` with the names of the tenant's offline forms bound to the entity.
```

After the paragraph starting "`template_fields` 对 `PageLayoutTemplates.find` 的结果" (zh-CN), add:

```markdown
将实体移入回收站时，会在同一事务中、在状态变更之前将其已上线表单下线：`soft_delete` 对每个 `Page.for_entity(id).launched` 调用 `take_offline!`，共享实体即覆盖所有租户的表单。`Page.for_entity` 以文本比较存储的绑定，因此 JSON 数字或字符串均能匹配。`forms_taken_offline` 记录下线数量，数量大于零时 `destroy` 在提示后追加 `maint_core.flash.entities.forms_taken_offline`。任一表单无法下线时，移入回收站整体回滚。恢复实体不会重新上线表单：`EntityRestorationsController#restored_notice` 会追加 `maint_core.flash.entity_restorations.offline_forms`，列出该租户中绑定此实体且仍处于下线状态的表单名称。
```

- [ ] **Step 6: Check the docs**

Run:

```bash
rg -n "Flowchart.accessible.referenceable" doc/reference/*/page-builder.md; rg -c "Pages::LaunchChecks" doc/reference/en/page-builder.md doc/reference/zh-CN/page-builder.md; rg -c "bound_to_flowchart" doc/reference/en/flowchart-builder.md doc/reference/zh-CN/flowchart-builder.md
```

Expected:
- the first command prints nothing;
- `Pages::LaunchChecks` appears the same number of times in both page-builder files;
- `bound_to_flowchart` appears the same number of times in both flowchart-builder files.

Then open `/81721200/admin/maintenance/platform/developer_docs` pages `page-builder`, `page-rendering`, `flowchart-builder` and `entity-builder` in both locales, if a dev server is running. Each should render the new sections without broken Markdown.

---

### Task 11: Verification

**Agent:** anysys-release-engineer

**Files:** none (runs commands only).

- [ ] **Step 1: Locale parity**

Run: `locale_parity maint_core admin_misc common` (define it from Global Constraints first).
Expected: no output.

- [ ] **Step 2: Leftover checks**

Run:

```bash
rg -n '"Additional"|"Other Fields"|"Linked: |label: "Divider"|label: "Spacer"|label: "Heading"|titleize' app/services/page_template_applier
rg -n "Flowchart\.accessible\.launched" app/services app/models
rg -n '\.to_i\)' app/models/page.rb
```

Expected:
- the first command prints nothing;
- the second prints only `app/services/pages/submission_process.rb` (and `public_submission.rb`'s `RuntimeGenerator#load_subflow_for_current_owner`, which loads subflows, not the page's flowchart);
- the third prints no `for_entity` line.

- [ ] **Step 3: Full suite**

Run: `bin/rails parallel:prepare && bin/rails parallel:spec`
Expected: 0 failures. Paste the summary lines.

- [ ] **Step 4: Assets and dev server**

Run: `bin/rails tailwindcss:build && rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000` in the background. Then run:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/81721200/admin/pages
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/81721200/admin/maintenance/flowcharts
```

Expected: `200` for both. Report PASS or FAIL with trimmed output. Do not commit.
