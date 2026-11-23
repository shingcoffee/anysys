# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::SendActivityUnsubscribe do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, customer: customer, email: "unsub-target@example.com") }

  it "round-trips a signed token for a user" do
    token = described_class.token_for(user)
    expect(described_class.find_user(token)).to eq(user)
  end

  it "records a campaign unsubscribe suppression" do
    token = described_class.token_for(user)
    described_class.unsubscribe(token)
    expect(Emails::Suppression.suppressed?(customer_id: user.customer_id, email: user.email)).to be(true)
  end

  it "returns nil for a tampered token" do
    expect(described_class.find_user("garbage")).to be_nil
    expect(described_class.emailed_address("garbage")).to be_nil
  end

  it "returns the emailed address after the profile email changes" do
    token = described_class.token_for(user)
    original = user.email
    user.update!(email: "new-inbox@example.com")

    expect(described_class.emailed_address(token)).to eq(Emails::Suppression.normalize(original))
    expect(described_class.find_user(token)).to eq(user)
  end

  it "returns nil (and does nothing) for a token whose user no longer exists" do
    token = described_class.token_for(user)
    user.destroy
    expect(described_class.unsubscribe(token)).to be_nil
  end

  it "uses the ledger recipient and tenant even after both profile values change" do
    message = build_stubbed(:email_message, :campaign, customer: customer, to: user.email,
                           metadata: { "user_id" => user.id })
    original_email = user.email
    user.update!(email: "new-inbox@example.com", customer: create(:customer))

    url = described_class.url_for_message(message)
    token = CGI.unescape(URI.parse(url).path.split("/").last)
    described_class.unsubscribe(token)

    expect(described_class.emailed_address(token)).to eq(original_email)
    expect(Emails::Suppression.suppressed?(customer_id: customer.id, email: original_email)).to be(true)
    expect(Emails::Suppression.suppressed?(customer_id: user.customer_id, email: original_email)).to be(false)
  end

  it "lets the campaign renderer supply an immutable envelope before the ledger is persisted" do
    token = described_class.token_for(user, email: "queued@example.com", customer_id: customer.id)
    described_class.unsubscribe(token)
    expect(Emails::Suppression.suppressed?(customer_id: customer.id, email: "queued@example.com")).to be(true)
  end

  it "preserves the canonical URL host, protocol and port" do
    allow(ActionMailer::Base).to receive(:default_url_options)
      .and_return(host: "mail.example.test", protocol: "https", port: 8443)

    expect(described_class.url_for(user)).to start_with("https://mail.example.test:8443/unsubscribe/")
  end

  it "does not fall back to the live profile when a signed payload lacks recipient fields" do
    token = described_class.verifier.generate({ "user_id" => user.id }, purpose: described_class::PURPOSE)
    expect(described_class.unsubscribe(token)).to be_nil
  end

  it "rejects a signed envelope without the required tenant rather than using the current profile tenant" do
    token = described_class.verifier.generate({ "user_id" => user.id, "email" => user.email }, purpose: described_class::PURPOSE)

    expect { expect(described_class.unsubscribe(token)).to be_nil }.not_to change(Emails::Suppression, :count)
    expect(described_class.emailed_address(token)).to be_nil
  end

  # B2: unify with the shared suppression ledger so the send-time gate
  # (Emails::Gateway.queue_for_send_activity) honours unsubscribes too.
  describe "unify with Emails::Suppression (B2)" do
    it "records a per-customer suppression with reason 'unsubscribe'" do
      token = described_class.token_for(user)

      described_class.unsubscribe(token)

      suppression = Emails::Suppression.find_by(customer_id: user.customer_id, email: user.email.downcase)
      expect(suppression).to be_present
      expect(suppression.reason).to eq("unsubscribe")
    end

    it "makes Emails::Suppression.suppressed? true for this user's email and customer afterwards" do
      token = described_class.token_for(user)

      described_class.unsubscribe(token)

      expect(Emails::Suppression.suppressed?(customer_id: user.customer_id, email: user.email)).to be true
    end

    it "does not suppress the same email under a different customer (per-customer scoping)" do
      other_customer = create(:customer)
      token = described_class.token_for(user)

      described_class.unsubscribe(token)

      expect(Emails::Suppression.suppressed?(customer_id: other_customer.id, email: user.email)).to be false
    end

    it "is idempotent — unsubscribing twice does not raise and leaves a single suppression row" do
      token = described_class.token_for(user)
      described_class.unsubscribe(token)

      expect { described_class.unsubscribe(token) }.not_to raise_error

      expect(
        Emails::Suppression.where(customer_id: user.customer_id, email: user.email.downcase).count
      ).to eq(1)
    end

    it "suppresses the emailed address, not a later profile email" do
      token = described_class.token_for(user)
      original = user.email
      user.update!(email: "new-inbox@example.com")

      described_class.unsubscribe(token)

      expect(Emails::Suppression.suppressed?(customer_id: user.customer_id, email: original)).to be true
      expect(Emails::Suppression.suppressed?(customer_id: user.customer_id, email: "new-inbox@example.com")).to be false
    end

    it "normalizes (downcases) the email when recording the suppression" do
      mixed_case_user = create(:user, customer: customer, email: "MixedCase@Example.com")
      token = described_class.token_for(mixed_case_user)

      described_class.unsubscribe(token)

      expect(Emails::Suppression.suppressed?(customer_id: customer.id, email: "mixedcase@example.com")).to be true
    end
  end

  describe ".resubscribe" do
    it "returns the user" do
      expect(described_class.resubscribe(user)).to eq(user)
    end

    it "removes the tenant-scoped 'unsubscribe' suppression row so sends stop being suppressed" do
      token = described_class.token_for(user)
      described_class.unsubscribe(token)
      expect(Emails::Suppression.suppressed?(customer_id: user.customer_id, email: user.email)).to be true

      described_class.resubscribe(user)

      expect(Emails::Suppression.suppressed?(customer_id: user.customer_id, email: user.email)).to be false
    end

    it "does not touch a bounce/complaint/manual suppression for the same email" do
      Emails::Suppression.record_for_customer!(customer_id: user.customer_id, email: user.email, reason: "hard_bounce")

      described_class.resubscribe(user)

      expect(
        Emails::Suppression.where(customer_id: user.customer_id, email: user.email.downcase, reason: "hard_bounce")
      ).to exist
    end

    # Suppression.upsert_row only sets the reason on create, so a resubscribe
    # must fully delete the row for a later unsubscribe to re-create it.
    it "supports the full unsubscribe → resubscribe → unsubscribe-again cycle" do
      token = described_class.token_for(user)

      described_class.unsubscribe(token)
      described_class.resubscribe(user)
      described_class.unsubscribe(token)

      expect(
        Emails::Suppression.where(customer_id: user.customer_id, email: user.email.downcase, reason: "unsubscribe").count
      ).to eq(1)
    end

    it "does not touch a global (customer_id NULL) suppression row" do
      Emails::Suppression.record_global!(email: user.email, reason: "unsubscribe")
      token = described_class.token_for(user)
      described_class.unsubscribe(token)

      described_class.resubscribe(user)

      expect(Emails::Suppression.where(customer_id: nil, email: user.email.downcase)).to exist
    end

    it "is idempotent — resubscribing a user with no suppression row does not raise" do
      expect { described_class.resubscribe(user) }.not_to raise_error
    end
  end
end
