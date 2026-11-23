# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Invocation, "submission handoff" do
  def result(status)
    Pages::Submit::Result.new(status: status)
  end

  it "restores the previous invocation when handoff raises" do
    previous = { module_key: "previous", input: { amount: 10 } }
    session = { described_class::SESSION_KEY => previous.deep_dup }
    expect do
      described_class.with_submission(session: session) do
        session[described_class::SESSION_KEY] = { module_key: "failed" }
        raise FeatureModules::RegistrationError, "failed"
      end
    end.to raise_error(FeatureModules::RegistrationError)
    expect(session[described_class::SESSION_KEY]).to eq(previous)
  end

  it "removes a newly staged invocation when the submission rolls back" do
    session = {}
    described_class.with_submission(session: session) do
      session[described_class::SESSION_KEY] = { entity_entry_id: 123 }
      result(:failed)
    end
    expect(session).not_to have_key(described_class::SESSION_KEY)
  end

  it "keeps the new invocation after a successful submission" do
    session = {}
    described_class.with_submission(session: session) do
      session[described_class::SESSION_KEY] = { entity_entry_id: 123 }
      result(:success)
    end
    expect(session[described_class::SESSION_KEY]).to eq(entity_entry_id: 123)
  end
end
