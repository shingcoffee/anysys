# frozen_string_literal: true

# Seed the first-party desktop OAuth client after boot. Schema loads do not
# replay data inserts, so this is the production equivalent of db:seed.
# Specs call Oauth::DesktopClient.ensure! themselves so test boot does not
# write to the database (parallel:prepare / transactional fixtures).
Rails.application.config.after_initialize do
  next if Rails.env.test?
  next unless defined?(ActiveRecord::Base)
  next unless ActiveRecord::Base.connected?
  next unless ActiveRecord::Base.connection.data_source_exists?("oauth_applications")

  Oauth::DesktopClient.ensure!
rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
  # Migrations have not created the tables yet.
end
