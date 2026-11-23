# frozen_string_literal: true

# Explicit test-only preload for the normal Rails server / job runner:
# bundle exec ruby -r ./spec/e2e/helpers/sdk_endpoints.rb bin/rails server ...
# Only documented SDK configuration is changed. No app/provider method is stubbed.
require "bundler/setup"
require "uri"
require "pathname"

abort "Local E2E environment required" unless %w[development test].include?(ENV.fetch("RAILS_ENV"))
root = Pathname.new(__dir__).join("../../..").realpath
database = Pathname.new(ENV.fetch("E2E_DATABASE_PATH")).expand_path(root)
abort "Dedicated app-local E2E database required" unless database.dirname == root.join("storage").realpath && database.basename.to_s.match?(/\A(?:browser|e2e)[\w.-]*\.sqlite3\z/)
abort "Database URL mismatch" unless ENV.fetch("DATABASE_URL") == "sqlite3:#{database}"
abort "ScriptedCompletion must be disabled" if ENV["E2E_STUB_ASSISTANT"] == "1"
endpoint = URI(ENV.fetch("E2E_PROVIDER_URL", "http://127.0.0.1:3012/v1"))
abort "Loopback HTTP provider required" unless endpoint.scheme == "http" && %w[127.0.0.1 localhost].include?(endpoint.host) && endpoint.path == "/v1" && !endpoint.userinfo && !endpoint.query && !endpoint.fragment

require "ruby_llm"
require "openai"
RubyLLM.configure { |config| config.openai_api_base = endpoint.to_s }
OpenAI.configure { |config| config.uri_base = endpoint.to_s }
