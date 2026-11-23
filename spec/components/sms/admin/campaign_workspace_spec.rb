# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS campaign workspace", type: :component do
  let(:customer) { build_stubbed(:customer, id: 81721200) }
  let(:campaign) { build_stubbed(:sms_campaign, customer: customer, created_by: build_stubbed(:user, customer: customer)) }
  let(:contact) { build_stubbed(:sms_contact, customer: customer) }
  let(:segment) { build_stubbed(:sms_segment, customer: customer) }
  let(:templates) { [{ id: 42, key: "offer", label: "Approved offer", required_vars: %w[name offer opt_out_url], body_template: nil }] }
  let(:contacts) { [{ id: contact.id, name: contact.name, phone_e164: contact.phone_e164 }] }
  let(:preview) do
    { matched_count: 3, eligible_count: 2, excluded_counts: { consent_missing: 1 }, deferred_counts: { quiet_hours: 2 },
      samples: [{ contact_id: contact.id, name: contact.name, phone_e164: contact.phone_e164,
                  vars: { "name" => "<script>sample</script>" }, rendered_body: nil, encoding: nil, units: nil, segments: nil,
                  eligible: true, reason: nil }], blockers: [], evaluated_at: Time.current, review_token: "signed-review" }
  end
  let(:campaign_values) do
    { name: "Unsaved offer", template_id: 42, segment_id: segment.id, variable_map_json: "{ invalid JSON",
      send_timing: "scheduled", scheduled_local: "2026-10-16T10:00", timezone: "Asia/Shanghai",
      quiet_hours_start: 21, quiet_hours_end: 9, frequency_window_hours: 24, send_rate_per_minute: 60,
      deadline_hours: 24, lock_version: campaign.lock_version }
  end

  before do
    allow(vc_test_controller).to receive(:current_customer_id).and_return(customer.id)
    allow(vc_test_controller).to receive(:current_user).and_return(nil)
  end

  def render_campaign_form(errors: {}, result: preview, values: campaign_values)
    render_inline(Sms::Admin::CampaignFormComponent.new(campaign: campaign, templates: templates,
      segments: [{ id: segment.id, name: segment.name }], contacts: contacts, form_values: values, preview: result, errors: errors))
  end

  def render_campaign_details(result: preview)
    render_inline(Sms::Admin::CampaignDetailsComponent.new(campaign: campaign, templates: templates,
      segments: [], contacts: contacts, preview: result, report: { cancelled_count: 2, attempted_count: 1 }, errors: {}))
  end

  %i[en zh-CN].each do |locale|
    context "in #{locale}" do
      around { |example| I18n.with_locale(locale) { example.run } }

      it "renders ordered, accessible sections and retains every submitted draft value" do
        render_campaign_form(errors: { variable_map: [I18n.t("sms_campaign_ui.shared.errors")] }, result: nil)
        expect(page).to have_css("form[data-controller='sms-campaign-wizard']")
        expect(page.all("[data-step]", visible: :all).map { |el| el["data-step"] }).to eq(%w[audience content schedule review])
        expect(page).to have_css("[data-step='content']:not(.hidden)")
        expect(page).to have_field("sms_campaign[name]", with: "Unsaved offer", visible: :all)
        expect(page).to have_field("sms_campaign[variable_map_json]", with: "{ invalid JSON")
        expect(page).to have_field("sms_campaign[scheduled_local]", with: "2026-10-16T10:00", visible: :all)
        expect(page).to have_css("#sms_campaign_variable_map_json[aria-invalid='true']")
        expect(page).to have_css("label[for='sms_campaign_variable_map_json']", text: I18n.t("sms_campaign_ui.fields.variable_map_json"))
        expect(page).to have_css("[role='alert'] a[href='#sms_campaign_variable_map_json']")
        expect(page).not_to have_text(I18n.t("sms_campaign_ui.campaigns.matched"))
        expect(page).not_to have_button(I18n.t("sms_campaign_ui.campaigns.launch"))
        expect(rendered_content).not_to include("translation_missing", "Translation missing")
      end

      it "isolates PATCH Save from POST Preview and posts the current fields" do
        render_campaign_form
        form = page.find("form")
        expect(form[:method]).to eq("post")
        expect(form).not_to have_css("input[name='_method']", visible: :all)
        save = form.find("button", text: I18n.t("sms_campaign_ui.campaigns.save_draft"), visible: :all)
        preview_button = form.find("button", text: I18n.t("sms_campaign_ui.campaigns.preview"), visible: :all)
        expect(save[:name]).to eq("_method")
        expect(save[:value]).to eq("patch")
        expect(save[:formaction]).to eq("/#{customer.id}/admin/modules/sms/campaigns/#{campaign.id}")
        expect(preview_button[:name]).to be_nil
        expect(preview_button[:formaction]).to eq("/#{customer.id}/admin/modules/sms/campaigns/#{campaign.id}/preview")
        expect(preview_button[:formmethod]).to eq("post")
        expect(form).to have_select("preview_contact_id", with_options: [contact.name], visible: :all)
      end

      it "does not claim missing provider text has a segment estimate and escapes samples" do
        render_campaign_form
        expect(rendered_content).to include(I18n.t("sms_campaign_ui.campaigns.preview_unavailable"))
        expect(rendered_content).to include(I18n.t("common.status.unknown"))
        expect(rendered_content).to include("&lt;script&gt;sample&lt;/script&gt;")
        expect(page).not_to have_css("script")
        expect(rendered_content).to include(I18n.t("sms_campaign_ui.reasons.quiet_hours"))
        expect(rendered_content).not_to include("translation_missing", "Translation missing")
      end

      it "launches only a saved, reviewed draft with version and token, without settings" do
        render_campaign_details
        form = page.find("form[action$='/launch']")
        expect(form[:method]).to eq("post")
        expect(form).to have_css("input[name='lock_version'][value='#{campaign.lock_version}']", visible: :all)
        expect(form).to have_css("input[name='review_token'][value='signed-review']", visible: :all)
        expect(form).not_to have_css("[name^='sms_campaign']", visible: :all)
        expect(form).not_to have_css("[name='commit'], [name='button']")
      end

      it "withholds launch when review is absent or blocked" do
        render_campaign_details(result: preview.merge(review_token: nil, blockers: [:template_required]))
        expect(page).not_to have_css("form[action$='/launch']")
        expect(page).to have_text(I18n.t("sms_campaign_ui.reasons.template_required"))
      end

      it "shows cancellation only on scheduled or running campaigns and retains report links" do
        campaign.status = "running"
        campaign.settings_snapshot = { "send_timing" => "immediate", "timezone" => "Asia/Shanghai" }
        render_campaign_details(result: nil)
        expect(page).to have_css("form[method='post'][action$='/cancel']")
        expect(page).to have_text(I18n.t("sms_campaign_ui.campaigns.cancel_help"))
        expect(page).to have_link(I18n.t("sms_campaign_ui.campaigns.report"), href: "/#{customer.id}/admin/modules/sms/campaigns/#{campaign.id}/report")
        expect(page).not_to have_css("form[action$='/launch']")
      end

      it "keeps contact editing separate from permission and retains malformed JSON" do
        render_inline(Sms::Admin::ContactFormComponent.new(contact: contact,
          form_values: { phone: "13800138000", country_code: "CN", timezone: "Asia/Shanghai", custom_attributes_json: "{bad", status: "active" },
          errors: { custom_attributes: [I18n.t("sms_campaign_ui.shared.errors")] }))
        expect(page).to have_field("sms_contact[phone]", with: "13800138000")
        expect(page).to have_field("sms_contact[custom_attributes_json]", with: "{bad")
        expect(page).not_to have_css("[name*='consent'], [name*='actor'], [name*='customer']")
        expect(page).to have_text(I18n.t("sms_audience.errors.phone_changed"))
        expect(page).to have_css(".grid.md\\:grid-cols-2")
      end

      it "posts append-only evidence and server-issued deduplication without protected fields" do
        render_inline(Sms::Admin::ConsentFormComponent.new(contact: contact, form_values: { action: "revoked", event_key: "server-issued-key", occurred_at: "2026-10-13T10:00:00+08:00", reference: "ticket-7" }, errors: {}))
        expect(page).to have_css("form[action$='/contacts/#{contact.id}/consent_events'][method='post']")
        expect(page).to have_css("input[name='sms_consent_event[event_key]'][value='server-issued-key']", visible: :all)
        expect(page).to have_select("sms_consent_event[action]", selected: I18n.t("sms_campaign_ui.contacts.revoke"))
        expect(page).not_to have_css("[name*='source'], [name*='phone'], [name*='actor'], [name*='customer'], [name='commit']")
      end

      it "keeps evidence readonly, including prior-phone events, and redacts provider evidence" do
        event = build_stubbed(:sms_consent_event, contact: contact, customer: customer, phone_e164: "+8613900139000",
          evidence: { "reference" => "record-1", "statement" => "<b>permission</b>", "raw" => "provider-secret" })
        render_inline(Sms::Admin::ContactDetailsComponent.new(contact: contact, consent_events: { records: [event], pagination: {} },
          eligibility: { eligible: false, reason: :consent_missing }, consent_form_values: { event_key: "key" }, errors: {}))
        expect(page).to have_text(event.phone_e164)
        expect(page).to have_text("<b>permission</b>")
        expect(page).not_to have_css("b")
        expect(rendered_content).not_to include("provider-secret")
        expect(page).not_to have_css("a[href*='consent_events/']")
        expect(page).to have_css("form input[name='lock_version']", visible: :all)
      end

      it "uses the SMS catalog and the existing builder without Email preview" do
        catalog = double(fields: [{ field: "phone_e164", label: I18n.t("sms_audience.fields.phone_e164"), type: :string, operators: %w[equals contains] }])
        segment.segment_rules = { "type" => "group", "conditions" => [{ "field" => "phone_e164", "operator" => "contains", "value" => "138" }], "joins" => [] }
        render_inline(Sms::Admin::SegmentFormComponent.new(segment: segment, catalog: catalog,
          form_values: { name: segment.name, segment_rules_json: JSON.generate(segment.segment_rules), lock_version: 7 }, preview: nil, errors: {}))
        expect(page).to have_css("[data-controller='segment-builder']")
        expect(page).to have_css("input[name='sms_segment[segment_rules_json]'][data-segment-builder-target='output']", visible: :all)
        expect(rendered_content).not_to include("email-list-form#preview")
        expect(page).not_to have_css("input[name='_method']", visible: :all)
        expect(page).to have_css("button[name='_method'][value='patch']")
        expect(page).to have_css("input[name='sms_segment[lock_version]'][value='7']", visible: :all)
        expect(page).to have_css("button[name='_method'][formaction$='/segments/#{segment.id}']")
        expect(page).to have_css("button[formaction$='/segments/#{segment.id}/preview'][formmethod='post']:not([name])")
      end

      it "uses collection preview and POST Save for a new segment" do
        new_segment = build(:sms_segment, customer: customer)
        render_inline(Sms::Admin::SegmentFormComponent.new(segment: new_segment, catalog: double(fields: []),
          form_values: { name: "New segment", segment_rules_json: "{}", lock_version: 0 }, preview: nil, errors: {}))
        expect(page).to have_css("form[action='/#{customer.id}/admin/modules/sms/segments'][method='post']")
        expect(page).to have_css("button[formaction$='/segments/preview'][formmethod='post']:not([name])")
        expect(page).not_to have_css("input[name='_method'], button[name='_method']", visible: :all)
      end

      it "preserves invalid rules without letting builder hydration broaden them" do
        render_inline(Sms::Admin::SegmentFormComponent.new(segment: segment, catalog: double(fields: []),
          form_values: { name: segment.name, segment_rules_json: "{broken" }, preview: nil, errors: { segment_rules_json: [I18n.t("sms_campaign_ui.shared.errors")] }))
        expect(page).to have_field("sms_segment[segment_rules_json]", with: "{broken")
        expect(page).not_to have_css("[data-controller='segment-builder']")
      end

      it "keeps an explicit Entity preview high-water mapping for execution and continuation" do
        values = { entity_id: 4, phone_field: "mobile", name_field: "full_name", country_code: "CN", timezone: "Asia/Shanghai", attribute_map_json: '{"city":"city"}', after_entry_id: 100 }
        result = { preview: true, scanned: 100, created: 90, updated: 8, unchanged: 0, invalid: 1, conflicts: 1, items: [{ entry_id: 101, contact_id: nil, outcome: :invalid, error_code: :invalid_phone }], through_entry_id: 345, next_after_entry_id: 200, has_more: true }
        props = { form_values: values, entities: [{ id: 4, label: "People" }], source_fields: { phone: [{ value: "mobile", label: "Mobile" }], scalar: [{ value: "full_name", label: "Name", type: :string }] }, sync_result: result, errors: {} }
        render_inline(Sms::Admin::EntitySyncComponent.new(**props))
        expect(page).to have_css("form[method='get'] select[name='entity_id']")
        execute = page.find("form[action$='/contacts/entity_sync']")
        expect(execute).to have_css("input[name='sms_entity_sync[through_entry_id]'][value='345']", visible: :all)
        expect(execute).to have_css("input[name='sms_entity_sync[after_entry_id]'][value='100']", visible: :all)
        expect(execute).to have_css("input[name='sms_entity_sync[phone_field]'][value='mobile']", visible: :all)
        expect(page).not_to have_css("[name*='consent'], [name='commit']")
        expect(page).to have_text(I18n.t("sms_campaign_ui.entity_sync.no_consent"))
        render_inline(Sms::Admin::EntitySyncComponent.new(**props.merge(sync_result: result.merge(preview: false))))
        next_form = page.all("form[action$='/contacts/entity_sync/preview']").last
        expect(next_form).to have_css("input[name='sms_entity_sync[after_entry_id]'][value='200']", visible: :all)
      end

      it "distinguishes report milestones, actual segment facts, and unknown delivery rate" do
        campaign.status = "completed"
        campaign.started_at = Time.current
        report = (Sms::Admin::CampaignReportComponent::MAIN_METRICS + Sms::Admin::CampaignReportComponent::OTHER_METRICS).index_with { 2 }
        report.merge!(skip_counts: { consent_missing: 1 }, deferred_counts: { quiet_hours: 1 }, provider_segments_total: 0, provider_segments_missing_count: 2, delivery_rate: nil)
        render_inline(Sms::Admin::CampaignReportComponent.new(campaign: campaign, report: report, records: [], columns: [], pagination: {}, filters: { status: "skipped", page: 2, per_page: 25 }))
        expect(page).to have_text(I18n.t("sms_campaign_ui.report.milestone_help"))
        expect(page).to have_text(I18n.t("sms_campaign_ui.report.segment_help"))
        expect(page).to have_text(I18n.t("common.status.unknown"))
        expect(page).to have_link(I18n.t("sms_campaign_ui.campaigns.csv"), href: "/#{customer.id}/admin/modules/sms/campaigns/#{campaign.id}/report.csv?status=skipped")
        expect(page).to have_css(".grid.xl\\:grid-cols-4")
        expect(rendered_content).not_to include("translation_missing", "Translation missing")
      end

      it "renders every directory from the exact record/column/pagination/filter props" do
        [Sms::Admin::CampaignsIndexComponent, Sms::Admin::ContactsIndexComponent, Sms::Admin::SegmentsIndexComponent].each do |component|
          render_inline(component.new(records: [], columns: [], pagination: { page: 1, per_page: 25, total: 0, total_pages: 1 }, filters: {}))
          expect(page).to have_css("turbo-frame#admin-table")
          expect(rendered_content).not_to include("translation_missing", "Translation missing")
        end
      end

      it "renders historical recipient facts with scoped links and no private payloads" do
        message = build_stubbed(:sms_message, customer: customer, status: "unknown", dispatch_started_at: Time.current,
          vars: { "secret" => "private-vars" }, raw_response: { "secret" => "private-provider" })
        recipient = build_stubbed(:sms_campaign_recipient, campaign: campaign, contact: contact, customer: customer,
          message: message, status: "admitted", contact_snapshot: { "name" => "Historical name" }, deferral_reason: "account_rate")
        columns = [{ key: :name, label: I18n.t("common.labels.name") },
                   { key: :status, label: I18n.t("sms_campaign_http.csv.recipient_status"), type: :badge },
                   { key: :message_status, label: I18n.t("sms_campaign_http.csv.message_status") }]
        render_inline(Sms::Admin::CampaignReportComponent.new(campaign: campaign, report: {}, records: [recipient],
          columns: columns, pagination: {}, filters: {}))
        expect(page).to have_link("Historical name", href: "/#{customer.id}/admin/modules/sms/contacts/#{contact.id}")
        expect(page).to have_link(I18n.t("sms_campaign_ui.report.message_details"), href: "/#{customer.id}/admin/modules/sms/messages/#{message.id}")
        expect(page).to have_text(I18n.t("sms_campaign_ui.reasons.account_rate"))
        expect(page).to have_text(I18n.t("common.status.unknown"))
        expect(rendered_content).not_to include("private-vars", "private-provider")
      end

      it "adds typed campaign/contact message links only for the URL tenant" do
        message = build_stubbed(:sms_message, customer: customer, campaign_id: campaign.id, contact_id: contact.id,
          vars: { "secret" => "private-value" })
        render_inline(Sms::Admin::MessageDetailsComponent.new(message: message))
        expect(page).to have_link(I18n.t("sms_campaign_ui.report.campaign_details"), href: "/#{customer.id}/admin/modules/sms/campaigns/#{campaign.id}")
        expect(page).to have_link(I18n.t("chrome.customer_card.contact"), href: "/#{customer.id}/admin/modules/sms/contacts/#{contact.id}")
        expect(rendered_content).not_to include("private-value")
        message.customer_id = customer.id + 1
        render_inline(Sms::Admin::MessageDetailsComponent.new(message: message))
        expect(page).not_to have_css("a[href*='/campaigns/'], a[href*='/contacts/']")
      end

      it "uses POST for creating a new draft and renders no method override or launch" do
        campaign.id = nil
        allow(campaign).to receive(:persisted?).and_return(false)
        render_campaign_form(result: nil)
        form = page.find("form")
        expect(form[:action]).to eq("/#{customer.id}/admin/modules/sms/campaigns")
        expect(form).not_to have_css("[name='_method']", visible: :all)
        expect(form).to have_css("button[value='preview'][formaction$='/campaigns/preview']", visible: :all)
        expect(form).not_to have_css("form[action$='/launch']")
      end

      it "renders audience tabs as an underline nav with one current page" do
        render_inline(Sms::Admin::TabsComponent.new(tabs: [
          { label: I18n.t("sms_campaign_http.navigation.contacts"), path: "/#{customer.id}/admin/modules/sms/contacts", active: true },
          { label: I18n.t("admin_modules.emails.segments.index.title"), path: "/#{customer.id}/admin/modules/sms/segments", active: false },
          { label: I18n.t("admin_modules.sms.opt_outs.title"), path: "/#{customer.id}/admin/modules/sms/opt_outs", active: false }
        ]))
        expect(page.all("nav a").map { |link| link[:href].split("/").last }).to eq(%w[contacts segments opt_outs])
        expect(page).to have_css("nav.overflow-x-auto a[aria-current='page']", count: 1)
        expect(page).to have_css("a.border-accent", count: 1)
      end

      it "renders masked unsubscribe GET confirmation and result states without admin links" do
        vc_test_controller.params[:token] = "signed-token"
        render_inline(Sms::UnsubscribeComponent.new(unsubscribe: { masked_phone: "+86••••8000", already_unsubscribed: false }, errors: {}))
        expect(page).to have_text("+86••••8000")
        expect(page).to have_css("form[action='/sms/unsubscribes/signed-token'][method='post']")
        expect(page).not_to have_link(href: /admin/)
        render_inline(Sms::UnsubscribeComponent.new(unsubscribe: { already_unsubscribed: false }, errors: {}))
        expect(page).to have_text(I18n.t("sms_campaign_ui.unsubscribe.success"))
        expect(page).not_to have_css("form")
        render_inline(Sms::UnsubscribeComponent.new(unsubscribe: nil, errors: { base: ["invalid"] }))
        expect(page).to have_text(I18n.t("sms_campaign_ui.unsubscribe.invalid_help"))
        expect(page).not_to have_css("form")
      end
    end
  end

  it "keeps paired UI locale keys and interpolation variables in parity" do
    flatten = lambda do |hash, prefix = []|
      hash.flat_map do |key, value|
        path = prefix + [key]
        value.is_a?(Hash) ? flatten.call(value, path).to_a : [[path.join("."), value.scan(/%\{([^}]+)\}/).flatten.sort]]
      end.to_h
    end
    values = %w[en zh-CN].map { |locale| YAML.safe_load_file(Rails.root.join("config/locales/sms_campaign_ui.#{locale}.yml")).fetch(locale) }
    expect(flatten.call(values.first)).to eq(flatten.call(values.last))
  end
end
