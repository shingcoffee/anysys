# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpeechToText::Activities::Transcribe do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, customer: customer) }

  let!(:settings) { create(:ai_assistant_provider_settings) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }
  let(:clip) { create(:speech_to_text_clip, :with_audio, :assistant, customer: customer, user: user, conversation: conversation) }

  before do
    enable_ai_assistant_module!(customer)
    Current.customer = customer
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(AiAssistant::Activities::SendMessage).to receive(:call).and_return(
      instance_double(
        "AiAssistant::Activities::SendMessage::Result",
        success?: true, errors: [], message: nil, http_status: 202
      )
    )
  end

  def stub_provider(outcome:, text: nil)
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:transcribe)
      .and_return(outcome: outcome, text: text, raw: {})
  end

  def broadcast_html
    html = nil
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do |*_args, **kwargs|
      html = kwargs[:html].to_s
    end
    yield
    html
  end

  it "hands a successful transcript to SendMessage and clears the composer payload" do
    stub_provider(outcome: :success, text: "hello")
    described_class.call(clip: clip)
    expect(AiAssistant::Activities::SendMessage).to have_received(:call).with(
      hash_including(customer: customer, user: user, body: "hello",
                     conversation_id: conversation.id, idempotency_key: "speech_to_text:clip:#{clip.id}")
    )
  end

  it "broadcasts the result to the signed stream, purges audio, and keeps the clip" do
    stub_provider(outcome: :success, text: "hello")
    clip_id = clip.id

    described_class.call(clip: clip)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      [ :ai_assistant, customer.id, user.id ],
      hash_including(target: "speech_to_text_result_#{clip_id}")
    )
    kept = SpeechToText::Clip.find_by(id: clip_id)
    expect(kept).to be_present
    expect(kept.status).to eq("succeeded")
    expect(kept.audio).not_to be_attached
  end

  it "does not construct OpenAI::Client when the provider is stubbed" do
    stub_provider(outcome: :success, text: "hello")
    expect(OpenAI::Client).not_to receive(:new)
    described_class.call(clip: clip)
  end

  it "maps :empty to a failed broadcast and keeps the clip" do
    stub_provider(outcome: :empty)
    clip_id = clip.id
    described_class.call(clip: clip)
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
    kept = SpeechToText::Clip.find_by(id: clip_id)
    expect(kept.status).to eq("failed")
    expect(kept.error_code).to eq("empty")
  end

  it "maps :unreachable to the translated vendor_down widget copy and still purges the clip" do
    stub_provider(outcome: :unreachable)
    clip_id = clip.id
    html = broadcast_html { described_class.call(clip: clip) }
    expect(html).to include(ERB::Util.html_escape(I18n.t("speech_to_text.widget.vendor_down")))
    kept = SpeechToText::Clip.find_by(id: clip_id)
    expect(kept.status).to eq("failed")
    expect(kept.error_code).to eq("vendor_down")
  end

  it "broadcasts disabled when no provider is active and still keeps the clip" do
    settings.deactivate_for!(:transcribe)
    clip_id = clip.id
    described_class.call(clip: clip)
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
    kept = SpeechToText::Clip.find_by(id: clip_id)
    expect(kept.status).to eq("failed")
    expect(kept.error_code).to eq("disabled")
  end

  it "does not call the STT vendor when the AI Assistant module is disabled" do
    FeatureModules::CustomerAssignment.where(customer: customer).delete_all
    expect_any_instance_of(AiAssistant::Providers::OpenaiWhisper).not_to receive(:transcribe)
    expect(AiAssistant::Activities::SendMessage).not_to receive(:call)

    described_class.call(clip: clip)

    expect(clip.reload.status).to eq("failed")
    expect(clip.error_code).to eq("disabled")
  end

  it "includes Stimulus result data attributes in the ResultComponent HTML" do
    stub_provider(outcome: :success, text: "hello")
    html = broadcast_html { described_class.call(clip: clip) }
    expect(html).to include("data-controller=\"speech-to-text-result\"")
    expect(html).to include("data-speech-to-text-result-field-id-value")
    expect(html).to include("data-speech-to-text-result-status-value")
    expect(html).to include("data-speech-to-text-result-transcript-value")
    expect(html).to include("data-speech-to-text-result-error-value")
  end

  # Regression: a successful transcript was ALWAYS forwarded to the assistant
  # and then blanked, so DictateFieldComponent mounted on any other field posted
  # the user's dictation into their assistant thread instead of filling the
  # field. The destination recorded at enqueue time now decides.
  describe "destination routing" do
    let(:field_clip) do
      create(:speech_to_text_clip, :with_audio, customer: customer, user: user,
             field_dom_id: "entity_entry_title")
    end

    it "broadcasts the transcript back to the field and never touches the assistant" do
      stub_provider(outcome: :success, text: "board minutes")
      html = broadcast_html { described_class.call(clip: field_clip) }

      expect(AiAssistant::Activities::SendMessage).not_to have_received(:call)
      expect(html).to include("board minutes")
      expect(html).to include("entity_entry_title")
      expect(field_clip.reload.status).to eq("succeeded")
    end

    it "sends an assistant clip's transcript to the chat and broadcasts no transcript payload" do
      stub_provider(outcome: :success, text: "board minutes")
      html = broadcast_html { described_class.call(clip: clip) }

      expect(AiAssistant::Activities::SendMessage).to have_received(:call)
        .with(hash_including(body: "board minutes"))
      expect(html).to include('data-speech-to-text-result-transcript-value=""')
    end

    it "reports the chat rate limit back to the widget for an assistant clip" do
      stub_provider(outcome: :success, text: "hello")
      allow(AiAssistant::Activities::SendMessage).to receive(:call).and_return(
        instance_double("AiAssistant::Activities::SendMessage::Result",
                        success?: false, errors: [], message: nil, http_status: 429)
      )

      described_class.call(clip: clip)
      expect(clip.reload.error_code).to eq("rate_limited")
    end
  end

  # Regression: an exception in persist/broadcast left status = "pending" with no
  # broadcast at all, so the widget span until PruneClipsJob deleted the row 15
  # minutes later and nothing was logged.
  describe "terminal state guarantees" do
    it "keeps recoverable processing state and audio when persistence fails" do
      stub_provider(outcome: :success, text: "hello")
      clip
      scope = double("processing scope")
      allow(SpeechToText::Clip).to receive(:where).and_call_original
      allow(SpeechToText::Clip).to receive(:where).with(id: clip.id, status: "processing").and_return(scope)
      allow(scope).to receive(:update_all).and_raise(ActiveRecord::StatementInvalid, "db gone")
      allow(Rails.logger).to receive(:error)

      described_class.call(clip: clip)

      expect(clip.reload.status).to eq("processing")
      expect(clip.audio).to be_attached
      expect(Rails.logger).to have_received(:error).with(/persisting outcome failed/)
    end

    it "terminalizes a routing exception before purging" do
      stub_provider(outcome: :success, text: "hello")
      allow(AiAssistant::Activities::SendMessage).to receive(:call).and_raise(RuntimeError, "routing down")
      described_class.call(clip: clip)
      expect(clip.reload).to have_attributes(status: "failed", error_code: "generic_error")
      expect(clip.audio).not_to be_attached
    end

    it "never redirects a clip whose pinned conversation has disappeared" do
      clip.update!(conversation: nil)
      stub_provider(outcome: :success, text: "hello")
      described_class.call(clip: clip)
      expect(AiAssistant::Activities::SendMessage).not_to have_received(:call)
      expect(clip.reload.status).to eq("failed")
    end

    it "does not transcribe or reroute a terminal clip on duplicate delivery" do
      stub_provider(outcome: :success, text: "hello")
      described_class.call(clip: clip)
      described_class.call(clip: clip.reload)
      expect(AiAssistant::Activities::SendMessage).to have_received(:call).once
      expect(clip.reload.status).to eq("succeeded")
    end

    it "does not steal or purge a clip already claimed by another worker" do
      clip.update!(status: "processing", started_at: Time.current)
      expect_any_instance_of(AiAssistant::Providers::OpenaiWhisper).not_to receive(:transcribe)
      described_class.call(clip: clip)
      expect(clip.reload.status).to eq("processing")
      expect(clip.audio).to be_attached
    end

    it "records a terminal status and logs when the vendor call raises" do
      allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:transcribe)
        .and_raise(RuntimeError, "boom")
      allow(Rails.logger).to receive(:error)

      described_class.call(clip: clip)

      expect(clip.reload.status).to eq("failed")
      expect(clip.error_code).to eq("generic_error")
      expect(Rails.logger).to have_received(:error).with(/vendor call failed.*RuntimeError: boom/)
    end

    it "logs and does not re-raise when the broadcast itself fails" do
      stub_provider(outcome: :success, text: "hello")
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(RuntimeError, "no redis")
      allow(Rails.logger).to receive(:error)

      expect { described_class.call(clip: clip) }.not_to raise_error
      expect(clip.reload.status).to eq("succeeded")
      expect(Rails.logger).to have_received(:error).with(/broadcast failed/)
    end

    it "purges the audio even when everything downstream fails" do
      stub_provider(outcome: :success, text: "hello")
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(RuntimeError, "no redis")
      allow(Rails.logger).to receive(:error)

      described_class.call(clip: clip)
      expect(clip.reload.audio).not_to be_attached
    end
  end
end
