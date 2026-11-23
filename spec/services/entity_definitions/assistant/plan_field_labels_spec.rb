# frozen_string_literal: true

require "rails_helper"

# Cross-layer guard: ChangePlan emits rows keyed by `field`, and
# AiAssistant::ProposedChangesComponent turns each one into a sentence the
# admin reads. Nothing connects the two at runtime, so this spec is the
# connection — it is the one place outside spec/components that may reference
# the component, because comparing the two vocabularies is the point of it.
#
# The plan no longer diffs an allowlist; it diffs two snapshots and reports
# whatever moved. Its vocabulary therefore grows the day a key is added to the
# schema, with nothing to remind anyone to add the wording. A field with no
# label is a real change the admin approves without reading it, and an entry
# whose every row is unlabelled leaves a confirmation prompt with no panel
# under it.
RSpec.describe "AI assistant change plan field labels" do
  labelled_locales = %i[en zh-CN]

  plan = EntityDefinitions::Assistant::ChangePlan
  component = AiAssistant::ProposedChangesComponent

  # Derived, never typed out: both lists come from the snapshot and the
  # normalizer allowlists, so a new key shows up here as a failure rather than
  # as a silent omission. The component keeps its own literal copy on purpose
  # — two independently maintained lists are the only way this spec can see
  # them drift apart.
  identity_fields = plan.identity_fields
  attribute_fields = plan.attribute_fields
  every_field = identity_fields | attribute_fields

  # A `field => "config"` row carries the specific setting under `config_key`,
  # bounded by what Normalizer lets an attribute config hold.
  config_keys = EntityDefinitions::Normalizer::INPUT_CONFIG_KEYS |
                EntityDefinitions::Normalizer::COMPUTED_CONFIG_KEYS

  def field_key(field) = "ai_assistant.assistant.plan.fields.#{field}"

  def config_key_key(key) = "ai_assistant.assistant.plan.config_fields.#{key}"

  # `fallback: false` is load-bearing. config.i18n.fallbacks is on
  # application-wide and applies to I18n.exists? as much as to I18n.t, so a
  # zh-CN key that was never written reports as existing and reads back the
  # English string. Without this option the check passes while a Chinese UI
  # shows English, which is the failure it is here to catch.
  def translated?(key, locale)
    I18n.exists?(key, locale, fallback: false) &&
      I18n.t(key, locale: locale, fallback: false, default: "").to_s.strip.present?
  end

  describe "every field the plan can emit is one the component words" do
    every_field.each do |field|
      it "lists #{field} in the component's field table" do
        expect(component::FIELDS).to include(field),
                                     "ChangePlan can emit a #{field.inspect} row, but " \
                                     "AiAssistant::ProposedChangesComponent::FIELDS does not list it, so the row " \
                                     "renders under the generic label instead of naming the field that changed."
      end
    end

    config_keys.each do |key|
      it "lists the #{key} config key in the component's config table" do
        expect(component::CONFIG_FIELDS).to include(key),
                                            "ChangePlan can emit a config row with config_key #{key.inspect}, but " \
                                            "AiAssistant::ProposedChangesComponent::CONFIG_FIELDS does not list it."
      end
    end
  end

  describe "every field the plan can emit is worded in every locale" do
    every_field.each do |field|
      labelled_locales.each do |locale|
        it "has a #{locale} label for the #{field} row" do
          expect(translated?(field_key(field), locale)).to eq(true),
                                                           "ChangePlan can emit a #{field.inspect} row, but " \
                                                           "#{field_key(field)} has no #{locale} translation. " \
                                                           "Add it to config/locales/ai_assistant.#{locale}.yml."
        end
      end
    end
  end

  describe "every config key the plan can name is worded in every locale" do
    config_keys.each do |key|
      labelled_locales.each do |locale|
        it "has a #{locale} label for the #{key} config key" do
          expect(translated?(config_key_key(key), locale)).to eq(true),
                                                              "ChangePlan can emit a config row with " \
                                                              "config_key #{key.inspect}, but " \
                                                              "#{config_key_key(key)} has no #{locale} translation."
        end
      end
    end
  end

  describe "the locales stay in parity" do
    %w[fields config_fields].each do |group|
      it "defines the same plan #{group} keys in en and zh-CN" do
        keys = labelled_locales.to_h do |locale|
          [locale, I18n.t("ai_assistant.assistant.plan.#{group}", locale: locale, default: {}).keys.map(&:to_s).sort]
        end

        expect(keys.fetch(:en)).to eq(keys.fetch(:"zh-CN")),
                                   "plan.#{group} differs between locales: " \
                                   "only en #{keys.fetch(:en) - keys.fetch(:'zh-CN')}, " \
                                   "only zh-CN #{keys.fetch(:'zh-CN') - keys.fetch(:en)}."
      end
    end

    # The generic labels the component falls back to are what keeps an
    # unrecognised field on screen rather than dropped, so they are required in
    # both locales like any other.
    %w[field_other config_field_other].each do |key|
      labelled_locales.each do |locale|
        it "has a #{locale} generic label for #{key}" do
          expect(translated?("ai_assistant.assistant.plan.#{key}", locale)).to eq(true)
        end
      end
    end

    it "can actually tell a missing translation from a present one" do
      expect(translated?(field_key("a_field_nobody_has_translated"), :en)).to eq(false)
      expect(translated?(field_key("a_field_nobody_has_translated"), :"zh-CN")).to eq(false)
    end

    # Proves the guard above is not fooled by the application-wide fallback:
    # a field translated only in en must read as untranslated in zh-CN.
    it "does not accept an English label standing in for a missing Chinese one" do
      I18n.backend.store_translations(
        :en,
        ai_assistant: { assistant: { plan: { fields: { en_only_probe_field: "probe" } } } }
      )

      expect(translated?(field_key("en_only_probe_field"), :en)).to eq(true)
      expect(translated?(field_key("en_only_probe_field"), :"zh-CN")).to eq(false)
    ensure
      # store_translations is process-global; left in place the probe key would
      # show up as a real en-only key in the parity check above.
      I18n.backend.reload!
    end
  end

  # Wording is only half of it. What matters to the admin is that the row
  # reaches the screen: a row the renderer drops is a change approved blind,
  # so an unrecognised field must fall back to a generic label rather than
  # disappear. These render one row at a time, so a drop names the field.
  describe "a row of every field survives rendering" do
    def panel_for(row)
      AiAssistant::ProposedChangesComponent.new(
        proposal: {
          "kind" => "operation",
          "plan" => [{ "name" => "Student", "id" => 1, "breaking" => false, "rows" => [row] }]
        }
      )
    end

    def expect_rendered(row, described_as)
      panel = panel_for(row)

      expect(panel.render?).to eq(true),
                               "ProposedChangesComponent dropped the only #{described_as} row, " \
                               "leaving a confirmation prompt with no panel under it."
      expect(panel.entries.flat_map(&:rows)).to be_present
    end

    identity_fields.each do |field|
      it "renders an identity row for #{field}" do
        expect_rendered(
          {
            "kind" => "identity", "action" => "modified", "field" => field,
            "before" => "before", "after" => "after", "breaking" => false
          },
          "identity/#{field}"
        )
      end
    end

    (attribute_fields - %w[options config]).each do |field|
      it "renders an attribute row for #{field}" do
        expect_rendered(
          {
            "kind" => "attribute", "action" => "modified", "name" => "Status", "field" => field,
            "before" => "before", "after" => "after", "breaking" => false
          },
          "attribute/#{field}"
        )
      end
    end

    config_keys.each do |key|
      it "renders a config row naming the #{key} key" do
        expect_rendered(
          {
            "kind" => "attribute", "action" => "modified", "name" => "Status",
            "field" => "config", "config_key" => key, "before" => "before", "after" => "after", "breaking" => false
          },
          "attribute/config/#{key}"
        )
      end
    end

    it "renders a config row that names no key at all" do
      expect_rendered(
        {
          "kind" => "attribute", "action" => "modified", "name" => "Status",
          "field" => "config", "before" => 2, "after" => 4, "breaking" => false
        },
        "attribute/config with no config_key"
      )
    end

    it "renders a config row whose key it has no specific wording for" do
      expect_rendered(
        {
          "kind" => "attribute", "action" => "modified", "name" => "Status",
          "field" => "config", "config_key" => "a_config_key_added_tomorrow",
          "before" => 2, "after" => 4, "breaking" => false
        },
        "attribute/config/unrecognised key"
      )
    end

    %w[added removed relabelled].each do |bucket|
      it "renders an options row carrying only #{bucket}" do
        buckets = { "added" => [], "removed" => [], "relabelled" => [] }
        buckets[bucket] = bucket == "relabelled" ? [{ "before" => "Applied", "after" => "Applied for" }] : ["Waitlisted"]

        expect_rendered(
          {
            "kind" => "attribute", "action" => "modified", "name" => "Status",
            "field" => "options", "breaking" => false
          }.merge(buckets),
          "attribute/options/#{bucket}"
        )
      end
    end

    # Removal is the most destructive action in a document and the one the
    # admin most needs to see.
    %w[group association].each do |kind|
      %w[added modified removed].each do |action|
        it "renders a #{kind} row for #{action}" do
          expect_rendered(
            { "kind" => kind, "action" => action, "name" => "Course", "breaking" => action == "removed" },
            "#{kind}/#{action}"
          )
        end
      end
    end

    it "renders an attribute_removed row" do
      expect_rendered(
        { "kind" => "attribute_removed", "action" => "removed", "name" => "Fax", "breaking" => true },
        "attribute_removed/removed"
      )
    end

    # The plan grows its own vocabulary as the schema grows. A field nobody has
    # worded yet must still reach the screen against a generic label, because
    # the alternative is the admin approving a change they were never shown.
    it "renders a row whose field it has no specific wording for" do
      expect_rendered(
        {
          "kind" => "attribute", "action" => "modified", "name" => "Status",
          "field" => "a_field_added_to_the_schema_tomorrow",
          "before" => "before", "after" => "after", "breaking" => false
        },
        "attribute/unrecognised field"
      )
    end

    it "renders an identity row whose field it has no specific wording for" do
      expect_rendered(
        {
          "kind" => "identity", "action" => "modified",
          "field" => "a_field_added_to_the_snapshot_tomorrow",
          "before" => "before", "after" => "after", "breaking" => false
        },
        "identity/unrecognised field"
      )
    end
  end

  # The membership checks above feed `"before" => "before"` strings, so they
  # never reach the shape dispatch that used to print Hash#inspect for a
  # Computed filter. These rows carry the values ChangePlan actually emits.
  describe "rendered values stay worded rather than inspected" do
    def html_for(row)
      ApplicationController.render(
        AiAssistant::ProposedChangesComponent.new(
          proposal: {
            "kind" => "operation",
            "plan" => [{ "name" => "Student", "id" => 1, "breaking" => false, "rows" => [row] }]
          }
        ),
        layout: false
      )
    end

    def expect_worded(html, described_as)
      expect(html).not_to include("=&gt;"),
                          "#{described_as} rendered Ruby hash-inspect output instead of worded chips."
    end

    it "words an object-valued config.filter row instead of showing a Ruby hash (I18n hard rule)" do
      html = html_for(
        "kind" => "attribute", "action" => "modified", "name" => "Score",
        "field" => "config", "config_key" => "filter",
        "before" => { "slug" => "score", "op" => "gt", "value" => 3 },
        "after" => { "slug" => "score", "op" => "gte", "value" => 5 },
        "breaking" => false
      )

      expect_worded(html, "config.filter")
      expect(html).to include(I18n.t("ai_assistant.assistant.plan.config_fields.op"))
    end

    it "words an audience map, a validator list, a bound source, and a boolean" do
      {
        "visibility" => [
          { "admin" => true, "member" => false, "public" => false },
          { "admin" => true, "member" => true, "public" => false }
        ],
        "validators" => [%w[presence], %w[format_email presence]],
        "options_source" => [
          { "kind" => "static" },
          { "kind" => "entity", "entity_name" => "Course" }
        ],
        "readonly" => [false, true]
      }.each do |field, (before, after)|
        html = html_for(
          "kind" => "attribute", "action" => "modified", "name" => "Status",
          "field" => field, "before" => before, "after" => after, "breaking" => false
        )
        expect_worded(html, field)
      end
    end
  end
end
