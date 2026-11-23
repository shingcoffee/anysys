# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::AccessToken do
  let_it_be(:customer) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer) }
  let(:application) { Oauth::DesktopClient.ensure! }

  # One row per token: Doorkeeper stores the access token and its refresh token
  # together, so a "family" is a set of these rows sharing family_started_at.
  def issue(family_started_at: Time.current, created_at: nil)
    token = described_class.create_for(
      application: application,
      resource_owner: user,
      scopes: Oauth::Protocol::SCOPE,
      expires_in: Oauth::Protocol::ACCESS_TOKEN_TTL.to_i,
      use_refresh_token: true,
      family_started_at: family_started_at
    )
    token.update_column(:created_at, created_at) if created_at
    token
  end

  def update_statements(&block)
    statements = []
    subscriber = lambda do |*, payload|
      statements << payload[:sql] if payload[:sql].to_s.start_with?("UPDATE")
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record", &block)
    statements
  end

  describe ".create_for" do
    it "stamps a server-issued family clock" do
      expect(issue(family_started_at: nil).family_started_at).to be_present
    end

    it "keeps the clock supplied by a refresh rotation" do
      started = 3.days.ago.change(usec: 0)
      expect(issue(family_started_at: started).family_started_at).to be_within(1.second).of(started)
    end

    it "cannot mint a token using an account instance from before a credential replacement" do
      stale = Authentication::User.find(user.id)
      user.update!(password: "NewPassword1!", password_confirmation: "NewPassword1!")

      expect {
        described_class.create_for(application: application, resource_owner: stale,
          scopes: Oauth::Protocol::SCOPE, expires_in: 3600, use_refresh_token: true)
      }.to raise_error(ActiveRecord::StaleObjectError)
      expect(described_class.where(resource_owner_id: user.id)).to be_empty
    end
  end

  describe "locked refresh consumption" do
    def refresh_request(token, raw)
      credentials = Doorkeeper::OAuth::Client::Credentials.new(application.uid, nil)
      Doorkeeper::OAuth::RefreshTokenRequest.new(Doorkeeper.config, token, credentials,
        refresh_token: raw, client_id: application.uid)
    end

    it "revokes the winner's replacement when a second preloaded gem exchange detects locked reuse" do
      original = issue
      raw = original.plaintext_refresh_token
      first = refresh_request(described_class.by_refresh_token(raw), raw)
      second = refresh_request(described_class.by_refresh_token(raw), raw)
      bystander = issue(family_started_at: 1.day.ago)

      first.authorize
      replacement = first.access_token
      expect(replacement).to be_present
      expect { second.authorize }.to raise_error(Doorkeeper::Errors::InvalidGrantReuse)

      expect(replacement.reload).to be_revoked
      expect(original.reload).to be_revoked
      expect(bystander.reload).not_to be_revoked
    end

    it "persists family revocation after rolling back a gem exchange's failing transaction" do
      original = issue
      sibling = issue(family_started_at: original.family_started_at)
      original_name = user.first_name

      expect {
        original.with_lock do
          user.update!(first_name: "Must roll back")
          raise Doorkeeper::Errors::InvalidGrantReuse
        end
      }.to raise_error(Doorkeeper::Errors::InvalidGrantReuse)

      expect(user.reload.first_name).to eq(original_name)
      expect(original.reload).to be_revoked
      expect(sibling.reload).to be_revoked
    end

    it "does not revoke a family when the exchange raises an unrelated error" do
      original = issue
      expect { original.with_lock { raise ArgumentError, "exchange failed" } }.to raise_error(ArgumentError)
      expect(original.reload).not_to be_revoked
    end

    it "rechecks refresh expiry after a live lookup" do
      original = issue
      stale = described_class.by_refresh_token(original.plaintext_refresh_token)
      original.update_column(:created_at, 91.days.ago)

      expect { stale.with_lock { raise "exchange must not run" } }
        .to raise_error(Doorkeeper::Errors::InvalidGrantReuse)
      expect(original.reload).to be_revoked
    end
  end

  describe ".by_refresh_token" do
    it "returns a live token untouched" do
      token = issue
      expect(described_class.by_refresh_token(token.plaintext_refresh_token)).to eq(token)
    end

    it "returns nil for an unknown refresh token" do
      expect(described_class.by_refresh_token("nope")).to be_nil
    end

    it "revokes the rest of the reused token's family" do
      started = 1.hour.ago
      original = issue(family_started_at: started)
      rotated = issue(family_started_at: started)
      original.revoke

      expect(described_class.by_refresh_token(original.plaintext_refresh_token)).to be_nil
      expect(rotated.reload).to be_revoked
    end

    it "leaves the same user's other sessions on the same client alive" do
      laptop = issue(family_started_at: 2.days.ago)
      phone = issue(family_started_at: 1.day.ago)
      laptop.revoke

      described_class.by_refresh_token(laptop.plaintext_refresh_token)

      expect(phone.reload).not_to be_revoked
    end

    it "revokes the whole family in a single UPDATE" do
      started = 1.hour.ago
      original = issue(family_started_at: started)
      2.times { issue(family_started_at: started) }
      original.revoke

      statements = update_statements do
        described_class.by_refresh_token(original.plaintext_refresh_token)
      end

      expect(statements.size).to eq(1)
      expect(described_class.where(revoked_at: nil).count).to eq(0)
    end

    it "revokes only itself when the family clock is unknown" do
      legacy = issue
      bystander = issue
      described_class.where(id: [legacy.id, bystander.id]).update_all(family_started_at: nil)
      legacy.reload.revoke

      described_class.by_refresh_token(legacy.plaintext_refresh_token)

      expect(bystander.reload).not_to be_revoked
    end

    it "revokes the family once the idle window has lapsed" do
      started = 100.days.ago
      stale = issue(family_started_at: started, created_at: 91.days.ago)
      sibling = issue(family_started_at: started)

      expect(described_class.by_refresh_token(stale.plaintext_refresh_token)).to be_nil
      expect(sibling.reload).to be_revoked
    end

    it "revokes the family once the absolute window has lapsed" do
      token = issue(family_started_at: 400.days.ago)

      expect(described_class.by_refresh_token(token.plaintext_refresh_token)).to be_nil
      expect(token.reload).to be_revoked
    end
  end

  describe "#refresh_expired?" do
    it "is false inside both windows" do
      expect(issue).not_to be_refresh_expired
    end

    it "falls back to created_at when no family clock is stored" do
      token = issue(created_at: 400.days.ago)
      described_class.where(id: token.id).update_all(family_started_at: nil)

      expect(token.reload).to be_refresh_expired
    end
  end

  describe ".revoke_all_for" do
    it "revokes every active token for that resource owner" do
      first = issue
      second = issue(family_started_at: 1.day.ago)

      described_class.revoke_all_for(user.id)

      expect(first.reload).to be_revoked
      expect(second.reload).to be_revoked
    end

    it "leaves an already-revoked token's revoked_at unchanged" do
      token = issue
      token.revoke
      original_revoked_at = token.reload.revoked_at

      travel_to(2.minutes.from_now) { described_class.revoke_all_for(user.id) }

      expect(token.reload.revoked_at).to eq(original_revoked_at)
    end

    it "does not revoke tokens belonging to another resource owner" do
      other = create(:user, :admin, customer: customer)
      foreign = described_class.create_for(
        application: application,
        resource_owner: other,
        scopes: Oauth::Protocol::SCOPE,
        expires_in: Oauth::Protocol::ACCESS_TOKEN_TTL.to_i,
        use_refresh_token: true
      )
      issue

      described_class.revoke_all_for(user.id)

      expect(foreign.reload).not_to be_revoked
    end

    it "is a no-op when the owner has no tokens" do
      stranger = create(:user, :admin, customer: customer)

      expect { described_class.revoke_all_for(stranger.id) }.not_to change {
        described_class.where(revoked_at: nil).count
      }
    end
  end
end
