# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::TrustedDevice do
  let(:customer) { Customer.find_or_create_by!(id: 81721200) { |c| c.name = "Plat"; c.industry = :technology; c.tier = :basic } }
  let(:user) do
    Authentication::User.create!(customer_id: customer.id, email: "a@x.com",
      password: "Password!234", first_name: "A", last_name: "B", confirmed_at: Time.current)
  end

  def issue(ip: nil, user_agent: nil)
    described_class.issue!(user: user, ip: ip, user_agent: user_agent)
  end

  describe ".issue! / .authenticate" do
    it "issues a row whose digest matches the returned raw token and authenticates it" do
      record, raw = issue(ip: "1.2.3.4", user_agent: "UA")
      expect(raw).to be_present
      expect(record.token_digest).to eq(Digest::SHA256.hexdigest(raw))
      expect(record.token_digest).not_to include(raw)
      expect(record.expires_at).to be > 29.days.from_now
      expect(described_class.authenticate(user: user, raw_token: raw)).to eq(record)
    end

    it "bumps last_used_at on a successful authenticate" do
      record, raw = issue
      record.update_column(:last_used_at, 2.days.ago)
      described_class.authenticate(user: user, raw_token: raw)
      expect(record.reload.last_used_at).to be > 1.minute.ago
    end

    it "returns nil for blank, expired, wrong-user and wrong-tenant tokens" do
      record, raw = issue
      expect(described_class.authenticate(user: user, raw_token: nil)).to be_nil
      expect(described_class.authenticate(user: user, raw_token: "")).to be_nil

      record.update_column(:expires_at, 1.minute.ago)
      expect(described_class.authenticate(user: user, raw_token: raw)).to be_nil
      record.update_column(:expires_at, 10.days.from_now)

      other = Authentication::User.create!(customer_id: customer.id, email: "c@x.com",
        password: "Password!234", first_name: "C", last_name: "D", confirmed_at: Time.current)
      expect(described_class.authenticate(user: other, raw_token: raw)).to be_nil
    end
  end

  describe ".active scope" do
    it "excludes expired rows" do
      live, = issue
      dead, = issue
      dead.update_column(:expires_at, 1.minute.ago)
      expect(described_class.active).to include(live)
      expect(described_class.active).not_to include(dead)
    end
  end

  it "refuses to recreate trust from a stale account after a password replacement" do
    stale = Authentication::User.find(user.id)
    user.update!(password: "NewPassword1!", password_confirmation: "NewPassword1!")

    expect { described_class.issue!(user: stale, ip: nil, user_agent: nil) }
      .to raise_error(ActiveRecord::StaleObjectError)
    expect(user.trusted_devices).to be_empty
  end
end
