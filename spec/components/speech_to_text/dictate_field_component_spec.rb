# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpeechToText::DictateFieldComponent, type: :component do
  let(:input_html) { %(<input id="field_name" type="text" data-speech-to-text-target="field">).html_safe }
  let(:user) { instance_double(Authentication::User, id: 9, admin_or_owner?: true) }
  let(:member) { instance_double(Authentication::User, id: 10, admin_or_owner?: false) }
  let(:customer) { instance_double(Customer, id: 12_345_678) }

  def stub_view_helpers(current_user:, current_customer: customer)
    helpers = double("helpers")
    allow(helpers).to receive(:current_user).and_return(current_user)
    allow(helpers).to receive(:current_customer).and_return(current_customer)
    allow(helpers).to receive(:form_authenticity_token).and_return("csrf-token")
    allow(helpers).to receive(:protect_against_forgery?).and_return(false)
    allow(helpers).to receive(:turbo_stream_from).and_return("".html_safe)
    allow(helpers).to receive(:t) { |key, **opts| opts[:default] || key }
    helpers
  end

  def enable_widget!(transcribe: true, generation: false)
    allow(FeatureModules::Module).to receive(:enabled?)
      .with(key: "ai_assistant", customer_id: customer.id)
      .and_return(true)
    transcribe_row = transcribe ? Object.new : nil
    generation_row = generation ? Object.new : nil
    stub_const("AiAssistant::ProviderSettings", Class.new do
      define_singleton_method(:active_for) do |job|
        case job.to_sym
        when :transcribe then transcribe_row
        when :generation then generation_row
        end
      end
    end)
  end

  describe "#render?" do
    let(:component) { described_class.new(field_id: "field_name") }

    it "is true when the user is admin-or-owner, the module is enabled, and a provider is configured" do
      allow(component).to receive(:helpers).and_return(stub_view_helpers(current_user: user))
      enable_widget!
      expect(component.render?).to be(true)
    end

    it "is false when the user is not admin-or-owner" do
      allow(component).to receive(:helpers).and_return(stub_view_helpers(current_user: member))
      enable_widget!
      expect(component.render?).to be(false)
    end

    it "is false when the module is disabled" do
      allow(component).to receive(:helpers).and_return(stub_view_helpers(current_user: user))
      allow(FeatureModules::Module).to receive(:enabled?).and_return(false)
      expect(component.render?).to be(false)
    end

    it "is false when ProviderSettings is not defined" do
      allow(component).to receive(:helpers).and_return(stub_view_helpers(current_user: user))
      allow(FeatureModules::Module).to receive(:enabled?).and_return(true)
      hide_const("AiAssistant::ProviderSettings")
      expect(component.render?).to be(false)
    end

    it "is false when ProviderSettings does not respond to active_for" do
      allow(component).to receive(:helpers).and_return(stub_view_helpers(current_user: user))
      allow(FeatureModules::Module).to receive(:enabled?).and_return(true)
      stub_const("AiAssistant::ProviderSettings", Class.new)
      expect(component.render?).to be(false)
    end

    it "is false when ProviderSettings.active_for(:transcribe) is blank" do
      allow(component).to receive(:helpers).and_return(stub_view_helpers(current_user: user))
      allow(FeatureModules::Module).to receive(:enabled?).and_return(true)
      stub_const("AiAssistant::ProviderSettings", Class.new do
        def self.active_for(_job) = nil
      end)
      expect(component.render?).to be(false)
    end

    it "is true when active_for(:transcribe) is present" do
      allow(component).to receive(:helpers).and_return(stub_view_helpers(current_user: user))
      enable_widget!(transcribe: true, generation: false)
      expect(component.render?).to be(true)
    end

    it "is false when only generation is assigned" do
      allow(component).to receive(:helpers).and_return(stub_view_helpers(current_user: user))
      enable_widget!(transcribe: false, generation: true)
      expect(component.render?).to be(false)
    end
  end

  describe "rendering" do
    it "wraps the input with a mic control when render? is true" do
      allow_any_instance_of(described_class).to receive(:show_widget?).and_return(true)
      allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_view_helpers(current_user: user))
      previous_customer = Current.customer
      Current.customer = customer

      render_inline(described_class.new(field_id: "field_name")) { input_html }

      expect(page).to have_css("[data-controller='speech-to-text']")
      expect(page).to have_css("input#field_name")
      expect(page).to have_css("button[data-speech-to-text-target='button'][data-action='click->speech-to-text#toggle']")
      expect(page).to have_css("button[aria-label='Dictate'][aria-pressed='false']")
      expect(page).to have_css("[data-speech-to-text-target='micIcon']")
      expect(page).to have_css("[data-speech-to-text-target='stopIcon'].hidden")
      expect(page).to have_css("[data-speech-to-text-target='liveDot']")
      expect(page).to have_css("[data-speech-to-text-target='status'][aria-live='polite']")
      expect(page).to have_css("[data-speech-to-text-target='inbox']")
      expect(page).to have_css("[data-speech-to-text-url-value='/12345678/admin/modules/ai_assistant/transcriptions']")
      expect(page).to have_css("[data-speech-to-text-max-duration-value='60']")
    ensure
      Current.customer = previous_customer
    end

    it "emits only the original input when render? is false" do
      allow_any_instance_of(described_class).to receive(:show_widget?).and_return(false)

      render_inline(described_class.new(field_id: "field_name")) { input_html }

      expect(page).to have_css("input#field_name")
      expect(page).not_to have_css("[data-controller='speech-to-text']")
      expect(page).not_to have_css("button[data-speech-to-text-target='button']")
    end

    it "places the mic and trailing actions in a composer toolbar" do
      allow_any_instance_of(described_class).to receive(:show_widget?).and_return(true)
      allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_view_helpers(current_user: user))
      previous_customer = Current.customer
      Current.customer = customer

      render_inline(described_class.new(field_id: "field_name", layout: :composer)) do |field|
        field.with_trailing_actions { "<button type='button'>Send</button>".html_safe }
        input_html
      end

      expect(page).to have_css("[data-controller='speech-to-text']")
      expect(page).to have_css("input#field_name")
      expect(page).to have_button("Send")
      expect(page).not_to have_css("button.absolute")
    ensure
      Current.customer = previous_customer
    end
  end

  describe "tenant max duration" do
    it "reads max_duration_seconds from the customer assignment when present" do
      assignment = instance_double(FeatureModules::CustomerAssignment, configuration_json: { "max_duration_seconds" => 90 })
      allow(FeatureModules::CustomerAssignment).to receive_message_chain(:joins, :find_by).and_return(assignment)
      component = described_class.new(field_id: "field_name")
      allow(component).to receive(:helpers).and_return(stub_view_helpers(current_user: user))
      expect(component.max_duration_seconds).to eq(90)
    end

    it "falls back to 60 when tenant config is unreadable" do
      component = described_class.new(field_id: "field_name")
      allow(component).to receive(:helpers).and_return(stub_view_helpers(current_user: nil, current_customer: nil))
      allow(Current).to receive(:customer_id).and_return(nil)
      expect(component.max_duration_seconds).to eq(60)
    end

    # Regression: the component clamped nothing, so a tenant configured above
    # the absolute ceiling let the browser record up to a limit the server would
    # then reject with `too_long`.
    it "advertises the same absolute ceiling the server enforces" do
      assignment = instance_double(FeatureModules::CustomerAssignment,
                                   configuration_json: { "max_duration_seconds" => 999 })
      allow(FeatureModules::CustomerAssignment).to receive_message_chain(:joins, :find_by).and_return(assignment)
      component = described_class.new(field_id: "field_name")
      allow(component).to receive(:helpers).and_return(stub_view_helpers(current_user: user))

      expect(component.max_duration_seconds).to eq(SpeechToText::DurationPolicy::ABSOLUTE_MAX_DURATION)
    end
  end

  describe "destination" do
    def render_with(destination)
      allow_any_instance_of(described_class).to receive(:show_widget?).and_return(true)
      allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_view_helpers(current_user: user))
      previous_customer = Current.customer
      Current.customer = customer
      render_inline(described_class.new(field_id: "field_name", destination: destination)) { input_html }
    ensure
      Current.customer = previous_customer
    end

    it "defaults to field so a reusable dictate control fills its own input" do
      render_with(nil)
      expect(page).to have_css("[data-speech-to-text-destination-value='field']")
    end

    it "emits an explicit assistant destination" do
      render_with(:assistant)
      expect(page).to have_css("[data-speech-to-text-destination-value='assistant']")
    end

    it "fails closed to field for an unknown destination" do
      render_with("elsewhere")
      expect(page).to have_css("[data-speech-to-text-destination-value='field']")
    end
  end

  it "declares the selected assistant thread and scoped selection-update action" do
    allow_any_instance_of(described_class).to receive(:show_widget?).and_return(true)
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_view_helpers(current_user: user))
    render_inline described_class.new(field_id: "field_name", destination: :assistant, conversation_id: 42) do
      input_html
    end
    expect(page).to have_css('[data-speech-to-text-conversation-id-value="42"][data-speech-to-text-destination-value="assistant"]')
    expect(page).to have_css('[data-action="ai-assistant:conversationChanged@window->speech-to-text#conversationChanged"]')
  end
end
