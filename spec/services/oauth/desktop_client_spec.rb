# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::DesktopClient do
  it "creates the public anysys-desktop application once" do
    first = described_class.ensure!
    second = described_class.ensure!

    expect(first.id).to eq(second.id)
    expect(first.uid).to eq("anysys-desktop")
    expect(first).not_to be_confidential
    expect(first.scopes.to_s).to eq("profile")
    expect(first.redirect_uri).to include("http://127.0.0.1/callback")
    expect(first.redirect_uri).to include("http://[::1]/callback")
  end

  # Secrets are hashed, so rotating one on boot would silently break every
  # deployed client. Doorkeeper only generates a secret `on: :create`.
  it "never rotates the stored secret" do
    stored = described_class.ensure!.secret

    expect(described_class.ensure!.reload.secret).to eq(stored)
  end

  it "writes nothing when the registration already matches the protocol" do
    described_class.ensure!

    expect { described_class.ensure! }
      .not_to change { Doorkeeper::Application.find_by(uid: "anysys-desktop").updated_at }
  end

  # Oauth::Protocol is the published contract; a locally widened registration
  # is intentionally pulled back to it rather than left to drift.
  it "restores a hand-widened redirect_uri" do
    app = described_class.ensure!
    app.update!(redirect_uri: "http://127.0.0.1/callback\nhttp://127.0.0.1/anything")

    expect(described_class.ensure!.redirect_uri).to eq(Oauth::Protocol::LOOPBACK_REDIRECT_URIS.join("\n"))
  end
end
