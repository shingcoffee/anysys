require_relative "boot"
require_relative "../lib/canonical_url_options"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Must be set before ActiveRecord loads models: the ruby_llm railtie reads
# this when including acts_as. We do not use acts_as_chat; this only avoids
# the legacy API deprecation on boot.
RubyLLM.configure do |config|
  config.use_new_acts_as = true
end

module Anysys
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks code_generators])

    # Environments parse APP_HOST/APP_PROTOCOL/APP_PORT once. Mail and PSP links
    # generated outside a request share the same validated application origin.
    config.after_initialize do |app|
      options = app.config.x.canonical_url_options.presence || app.config.action_mailer.default_url_options
      canonical = CanonicalUrlOptions.validate(options, production: Rails.env.production?)
      app.default_url_options.merge!(canonical)
      app.config.action_mailer.default_url_options = canonical
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # ---- Internationalization ------------------------------------------------
    # Two UI languages: English (default) and Simplified Chinese. Missing
    # zh-CN keys fall back to en so a raw translation key is never shown.
    config.i18n.available_locales = [:en, :"zh-CN"]
    config.i18n.default_locale    = :en
    config.i18n.fallbacks         = true
    # Load namespaced locale files from nested directories too.
    config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.{rb,yml}")]
  end
end
