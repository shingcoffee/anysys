source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Modern Action Text rich-text editor (Lexical-based) [https://github.com/basecamp/lexxy]
gem "lexxy", "~> 0.9.27"
# ViewComponent for component architecture [https://viewcomponent.org]
gem "view_component"
# Dry-types for type system [https://dry-rb.org/gems/dry-types]
gem "dry-types"
# Rouge for syntax highlighting [https://github.com/rouge-ruby/rouge]
gem "rouge"
# Developer reference: GitHub-flavored Markdown to HTML, hosted in-app for the
# platform owner. Kramdown assigns heading ids and Rouge colors fenced code.
gem "kramdown", "~> 2.4"
gem "kramdown-parser-gfm", "~> 1.1"
# Pagy for pagination math (wrapped by ModuleEntriesResolver / Member::PageFilters) [https://ddnexus.github.io/pagy/]
gem "pagy", "~> 9.3"
# Faraday HTTP client (wrapped by Vendor::HttpClient) [https://lostisland.github.io/faraday/]
gem "faraday", "~> 2.12"
# Standards-compliant multipart encoding for OutboundHttp
gem "faraday-multipart", "~> 1.2"
# Dentaku safe formula evaluation (wrapped by FlowchartRuntime::ExpressionEvaluator) [https://github.com/rubysolo/dentaku]
gem "dentaku", "~> 3.5"
# JWT encode/decode (wrapped by FlowchartRuntime::Jwt) [https://github.com/jwt/ruby-jwt]
gem "jwt", "~> 3.2"
# Money: ISO 4217 symbols, subunit math, zero-decimal awareness (wrapped by Billing::CurrencyResolver) [https://github.com/RubyMoney/money]
gem "money", "~> 6.19"
# I18n: locale data (plurals, date/number formats) for en + zh-CN [https://github.com/svenfuchs/rails-i18n]
gem "rails-i18n", "~> 8.0"
# URI parsing for marketing hrefs (wrapped by Websites::Href)
gem "addressable", "~> 2.8"
# Parse the Accept-Language header for the locale resolution fallback chain [https://github.com/iain/http_accept_language]
gem "http_accept_language", "~> 2.1"
# Trailblazer for business logic organization [https://trailblazer.to]
gem "trailblazer-activity"
gem "trailblazer-activity-dsl-linear"
gem "trailblazer-developer"

# Password hashing for flowchart security steps and has_secure_password
gem "bcrypt", "~> 3.1"
gem "scrypt", "~> 3.1"
gem "argon2", "~> 2.3"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "fugit"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# DKIM signing for outgoing email (Email::DkimSigner wraps it)
gem "dkim", "~> 1.1"

# Official Stripe API client (wrapped by Payments::Gateways::Stripe)
gem "stripe", "~> 19.3"
# Official Twilio REST client + webhook request validation (wrapped by Sms::Adapters::Twilio)
gem "twilio-ruby", "~> 7.10"
# Google libphonenumber numbering-plan data (wrapped by Sms::PhoneNumber)
gem "phonelib", "~> 0.10.27"
# ISO 13616 IBAN structure per country (wrapped by FlowchartRuntime::ValueValidator)
gem "ibandit", "~> 1.37"
# Official OpenAI Ruby client (Whisper STT only; wrapped by AiAssistant::Providers::OpenaiWhisper)
gem "ruby-openai", "~> 8.1"
# Unified chat/completions (wrapped by Llm). Not used for Whisper transcription.
gem "ruby_llm", "~> 1.16"
# JSON Schema validation for the assistant entity-fill envelope
gem "json_schemer", "~> 2.4"
# Official AWS Transcribe Streaming client (wrapped by AiAssistant::Providers::AwsTranscribe).
# http-2 is required by AsyncClient's bidirectional HTTP/2 event stream.
gem "aws-sdk-transcribestreamingservice", "~> 1.0"
# Official AWS Bedrock Runtime client (wrapped by AiAssistant::Providers::AwsBedrock).
gem "aws-sdk-bedrockruntime", "~> 1.0"
gem "http-2", "~> 1.0"
# Official AWS SESv2 send + SNS webhook verification (wrapped by Email::Providers::Ses)
gem "aws-sdk-sesv2", "~> 1.0"
gem "aws-sdk-sns", "~> 1.0"
group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # RSpec testing framework
  gem "rspec-rails"
  gem "factory_bot_rails"

  # Run the suite across all CPU cores [https://github.com/grosser/parallel_tests]
  gem "parallel_tests", require: false

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # RSpec-specific cops [https://github.com/rubocop/rubocop-rspec]
  gem "rubocop-rspec", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Code coverage measurement, line + branch [https://github.com/simplecov-ruby/simplecov]
  gem "simplecov", require: false
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  # CDP-based Capybara driver (Ferrum) — replaces selenium-webdriver: no
  # chromedriver binary to version-match, faster startup, more stable waits.
  gem "cuprite"
  # Rails controller testing helpers (assigns, render_template)
  gem "rails-controller-testing"
  # HTTP request stubbing for tests [https://github.com/bblimke/webmock]
  gem "webmock"
  # Factory/DB profiling + let_it_be/before_all + factory_default: cuts the
  # FactoryBot `create` churn that dominates suite wall-time [https://test-prof.evilmartians.io]
  gem "test-prof"
  # Isolated ENV mutation in specs [https://github.com/thoughtbot/climate_control]
  gem "climate_control"
end

gem "reform", "~> 2.6"
gem "reform-rails", "~> 0.3.1"

# CanCanCan — authorization framework for RBAC
gem "cancancan", "~> 3.6"

# Authentication
gem "devise", "~> 5.0"
# Devise translations for English and Chinese (zh-CN)
gem "devise-i18n", "~> 1.13"
# OAuth 2.0 authorization server (PKCE for the first-party desktop GUI)
gem "doorkeeper", "~> 5.8"
# TOTP-based 2FA/MFA
gem "rotp", "~> 6.3"
gem "rqrcode", "~> 2.2"

# Archive compress/decompress (wrapped by FlowchartRuntime::Archive) [https://github.com/rubyzip/rubyzip]
gem "rubyzip", "~> 3.0"

# Barcode generation for flowchart barcode_generate steps (wrapped by FlowchartRuntime::Barcode)
gem "barby", "~> 0.7"
gem "mini_magick", "~> 5.3"
# Liquid templates for flowchart template_render steps (wrapped by FlowchartRuntime::Template)
gem "liquid", "~> 5.5"
# HTML sanitization modes used directly by FlowchartRuntime::Sanitize
gem "loofah", "~> 2.24"

# File generation for flowchart generate_file steps (wrapped by FlowchartRuntime::FileGenerate)
gem "builder", "~> 3.3"
gem "caxlsx", "~> 4.2"
gem "prawn", "~> 2.5"

# ULID generation for flowchart generate_id steps (wrapped by FlowchartRuntime::Id)
gem "ulid", "~> 1.4"
# Nanoid generation for flowchart generate_id steps (wrapped by FlowchartRuntime::Id)
gem "nanoid", "~> 2.0"

# Base58 encoding for flowchart generate_token base58 type
gem "base58", "~> 0.2"

# Parallel map/each for flowchart collection / parallel_for_each steps
gem "parallel", "~> 1.26"
# Structured hash diffs for compare_data step
gem "hashdiff", "~> 1.1"
# TOML parse/serialize for parse_data / serialize paths
gem "toml-rb", "~> 3.0"

# Front-of-app per-IP URL throttling (captcha challenge after the limit)
gem "rack-attack", "~> 6.7"
