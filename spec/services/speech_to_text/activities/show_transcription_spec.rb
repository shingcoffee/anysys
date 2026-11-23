# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpeechToText::Activities::ShowTranscription do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }

  before { Current.customer = customer }

  it "returns the clip owned by the user in that tenant" do
    clip = create(:speech_to_text_clip, customer: customer, user: user)
    result = described_class.call(customer: customer, user: user, clip_id: clip.id)
    expect(result.success?).to eq(true)
    expect(result.clip).to eq(clip)
  end

  it "returns 404 when the clip belongs to another user" do
    other = create(:user, :admin, customer: customer)
    clip = create(:speech_to_text_clip, customer: customer, user: other)
    result = described_class.call(customer: customer, user: user, clip_id: clip.id)
    expect(result.http_status).to eq(404)
    expect(result.clip).to be_nil
  end

  it "returns 404 when the clip belongs to another tenant" do
    other = create(:customer)
    stranger = create(:user, :admin, customer: other)
    clip = create(:speech_to_text_clip, customer: other, user: stranger)
    result = described_class.call(customer: customer, user: user, clip_id: clip.id)
    expect(result.http_status).to eq(404)
  end

  it "returns 404 when the clip is missing" do
    result = described_class.call(customer: customer, user: user, clip_id: -1)
    expect(result.http_status).to eq(404)
  end
end
