# frozen_string_literal: true

module Oauth
  # Idempotent seed for the single first-party public client. Schema loads
  # do not replay data inserts, so tests and `db:seed` call `.ensure!`.
  #
  # Oauth::Protocol is the source of truth for every attribute here: a
  # hand-widened redirect_uri or renamed client is reset on the next boot,
  # deliberately, so the registered client cannot drift away from the published
  # protocol. The hashed secret is *not* touched — Doorkeeper generates one only
  # `on: :create` (and skips generation when one is present), so re-running this
  # can never rotate it.
  class DesktopClient
    def self.ensure!
      app = Doorkeeper::Application.find_or_initialize_by(uid: Protocol::CLIENT_ID)
      app.name = Protocol::CLIENT_NAME
      app.redirect_uri = Protocol::LOOPBACK_REDIRECT_URIS.join("\n")
      app.confidential = false
      app.scopes = Protocol::SCOPE
      app.save! if app.new_record? || app.changed?
      app
    end
  end
end
