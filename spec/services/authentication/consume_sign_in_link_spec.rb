# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::ConsumeSignInLink do
  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }
  let(:user) { create(:user, customer: customer, email: "link@example.com") }

  before { ensure_customer_feature_module(customer, auth_module, status: :active) }

  def issue
    raw, hashed = Devise.token_generator.generate(Authentication::User, :sign_in_token)
    user.update_columns(sign_in_token: hashed, sign_in_token_sent_at: Time.current)
    raw
  end

  it "consumes a valid token once" do
    raw = issue
    result = described_class.call(token: raw)

    expect(result.success?).to be(true)
    expect(result.user).to eq(user)
    expect(user.reload.sign_in_token).to be_nil

    replay = described_class.call(token: raw)
    expect(replay.success?).to be(false)
  end

  it "rejects an expired token" do
    raw = issue
    user.update_columns(sign_in_token_sent_at: 16.minutes.ago)

    result = described_class.call(token: raw)
    expect(result.success?).to be(false)
    expect(user.reload.sign_in_token).to be_present
  end

  it "rejects a blank or unknown token" do
    expect(described_class.call(token: "").success?).to be(false)
    expect(described_class.call(token: "nope").success?).to be(false)
  end

  # The token used to be cleared with a read-then-update pair, so two requests
  # arriving together both passed the read and both succeeded — the "one-time"
  # link was not one-time under concurrency. Consumption is now a conditional
  # UPDATE, so exactly one caller can match the row.
  describe "single-use under concurrency" do
    it "lets exactly one of two interleaved consumers win" do
      raw = issue
      first = described_class.new(token: raw)
      second = described_class.new(token: raw)

      # Both instances read the row before either claims it. Stubbing the
      # lookup for the second consumer reproduces that interleaving
      # deterministically: it holds a live, unconsumed record in memory and
      # only then attempts its own claim.
      stale = Authentication::User.find(user.id)
      allow(Authentication::User).to receive(:find_by)
        .with(hash_including(:sign_in_token)).and_return(stale)

      results = [ first.call, second.call ]

      expect(results.count(&:success?)).to eq(1)
      expect(user.reload.sign_in_token).to be_nil
    end

    it "reports failure when the row was already claimed" do
      raw = issue
      consumer = described_class.new(token: raw)
      allow(Authentication::User).to receive(:find_by)
        .with(hash_including(:sign_in_token))
        .and_return(Authentication::User.find(user.id))

      Authentication::User.where(id: user.id)
                          .update_all(sign_in_token: nil, sign_in_token_sent_at: nil)

      expect(consumer.call.success?).to be(false)
    end
  end

  # Eligibility used to be checked by SignInFlow AFTER the token had already
  # been cleared, so a user who could never sign in lost their link anyway and
  # had to request a new one that would fail identically.
  describe "eligibility pre-flight (token is not burnt on a hopeless request)" do
    it "rejects an unconfirmed user without consuming the token" do
      raw = issue
      user.update_columns(confirmed_at: nil)

      expect(described_class.call(token: raw).success?).to be(false)
      expect(user.reload.sign_in_token).to be_present
    end

    it "rejects a deactivated user without consuming the token" do
      raw = issue
      user.update!(status: :inactive)

      expect(described_class.call(token: raw).success?).to be(false)
      expect(user.reload.sign_in_token).to be_present
    end

    it "rejects a locked-out user without consuming the token" do
      raw = issue
      user.update!(locked_at: Time.current, failed_attempts: Devise.maximum_attempts)

      expect(described_class.call(token: raw).success?).to be(false)
      expect(user.reload.sign_in_token).to be_present
    end

    it "rejects a user whose tenant has authentication disabled without consuming the token" do
      raw = issue
      FeatureModules::CustomerAssignment
        .where(customer: customer, feature_module: auth_module).delete_all

      expect(described_class.call(token: raw).success?).to be(false)
      expect(user.reload.sign_in_token).to be_present
    end
  end

  it "leaves the returned record consistent with the cleared columns" do
    result = described_class.call(token: issue)

    expect(result.user.sign_in_token).to be_nil
    expect(result.user.sign_in_token_sent_at).to be_nil
  end

  it "rejects a link lookup from before a password reset instead of trusting its stale eligibility" do
    raw = issue
    stale = Authentication::User.find(user.id)
    user.update!(password: "NewPassword1!", password_confirmation: "NewPassword1!")
    allow(Authentication::User).to receive(:find_by).with(hash_including(:sign_in_token)).and_return(stale)

    expect(described_class.call(token: raw).success?).to be(false)
    expect(user.reload.sign_in_token).to be_nil
  end

  it "rechecks deactivation after the initial token lookup without burning the link" do
    raw = issue
    stale = Authentication::User.find(user.id)
    user.update!(status: :inactive)
    allow(Authentication::User).to receive(:find_by).with(hash_including(:sign_in_token)).and_return(stale)

    expect(described_class.call(token: raw).success?).to be(false)
    expect(user.reload.sign_in_token).to be_present
  end
end
