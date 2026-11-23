# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::HandoffEntryComponent, type: :component do
  let(:submit_url) { "/12345678/handoff" }
  let(:scope) { "comp_payments.handoff_entry" }

  def field(name, type: "string", validates: {})
    FeatureModules::HandoffField.new(name: name, validates: validates, type: type, source: "user_fillable")
  end

  def render_component(fields: [ field("body") ], values: {}, errors: nil, i18n_scope: scope)
    render_inline(described_class.new(fields: fields, values: values, errors: errors,
                                      i18n_scope: i18n_scope, submit_url: submit_url))
  end

  it "renders a labelled input per field in a PATCH form that leaves Turbo Drive" do
    render_component
    expect(page).to have_css("form[action='#{submit_url}'][data-turbo='false']")
    expect(page).to have_css("input[name='_method'][value='patch']", visible: :hidden)
    expect(page).to have_css("textarea[name='handoff[body]']")
    expect(page).to have_text(I18n.t("comp_payments.handoff_entry.fields.body.label"))
    expect(page).to have_button(I18n.t("comp_payments.handoff_entry.continue"))
  end

  it "prefills the field from values" do
    render_component(values: { "body" => "existing note" })
    expect(page).to have_css("textarea[name='handoff[body]']", text: "existing note")
  end

  it "renders errors when present" do
    errors = double(any?: true, full_messages: [ "Body is too long" ])
    render_component(errors: errors)
    expect(page).to have_css("[role='alert']", text: "Body is too long")
  end

  it "falls back to the generic copy when the module scope has none" do
    I18n.backend.store_translations(:en, demo_scope: { fields: { phone: { label: "Phone" } } })
    render_component(fields: [ field("phone") ], i18n_scope: "demo_scope")
    expect(page).to have_text(I18n.t("feature_modules.handoff_entry.title"))
    expect(page).to have_text(I18n.t("feature_modules.handoff_entry.subtitle"))
    expect(page).to have_button(I18n.t("feature_modules.handoff_entry.continue"))
  ensure
    I18n.reload!
  end

  describe "controls by declared contract type" do
    around do |example|
      I18n.backend.store_translations(:en, demo_scope: { fields: %w[plan seats rate email opt_in at].index_with { |n| { label: n.titleize } } })
      example.run
    ensure
      I18n.reload!
    end

    let(:fields) do
      [
        field("plan", type: "enum", validates: { presence: true, inclusion: { in: %w[basic pro] } }),
        field("seats", type: "integer", validates: { presence: true }),
        field("rate", type: "number"),
        field("email", type: "email"),
        field("opt_in", type: "boolean"),
        field("at", type: "datetime")
      ]
    end

    before do
      render_component(fields: fields, i18n_scope: "demo_scope", values: {
        "plan" => "pro", "seats" => 3, "rate" => 1.5, "email" => "a@b.test", "opt_in" => "true",
        "at" => "2026-12-01T09:30:00"
      })
    end

    it "renders an enum as a select of its allowed values" do
      expect(page).to have_select("handoff[plan]", options: %w[basic pro], selected: "pro")
      expect(page).to have_css("select[name='handoff[plan]'][required]")
    end

    it "renders integers and numbers as number inputs with the right step" do
      expect(page).to have_css("input[type='number'][name='handoff[seats]'][step='1'][required][value='3']")
      expect(page).to have_css("input[type='number'][name='handoff[rate]'][step='any'][value='1.5']")
    end

    it "renders email, boolean and datetime controls" do
      expect(page).to have_css("input[type='email'][name='handoff[email]'][value='a@b.test']")
      expect(page).to have_css("input[type='checkbox'][name='handoff[opt_in]'][checked]")
      expect(page).to have_css("input[type='hidden'][name='handoff[opt_in]'][value='0']", visible: :hidden)
      expect(page).to have_css("input[type='datetime-local'][name='handoff[at]'][value='2026-12-01T09:30']")
    end
  end

  it "leaves an unparseable datetime empty" do
    I18n.backend.store_translations(:en, demo_scope: { fields: { at: { label: "At" } } })
    render_component(fields: [ field("at", type: "datetime") ], i18n_scope: "demo_scope", values: { "at" => "soon" })
    expect(page).to have_css("input[type='datetime-local'][name='handoff[at]']")
    expect(page).not_to have_css("input[name='handoff[at]'][value='soon']")
  ensure
    I18n.reload!
  end

  it "resolves all copy in zh-CN" do
    I18n.with_locale(:"zh-CN") { render_component }
    expect(page).to have_text("添加备注")
  end
end
