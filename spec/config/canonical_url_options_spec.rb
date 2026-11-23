# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe CanonicalUrlOptions do
  it "normalizes already-parsed host/protocol/port options without reading the environment again" do
    options = described_class.validate({ host: "payments.example.test", protocol: "HTTPS", port: "8443" }, production: true)
    expect(options).to eq(host: "payments.example.test", protocol: "https", port: 8443)
  end

  it "allows the configured development origin" do
    expect(described_class.validate({ host: "localhost", protocol: "http", port: 3000 }, production: false))
      .to eq(host: "localhost", protocol: "http", port: 3000)
  end

  [nil, "", "http://payments.example.test", "payments.example.test/path", "user:password@payments.example.test",
   "payments.example.test?token=secret", "payments.example.test:8443", "bad host"].each do |host|
    it "rejects an invalid production authority #{host.inspect}" do
      expect { described_class.validate({ host: host, protocol: "https" }, production: true) }.to raise_error(ArgumentError)
    end
  end

  %w[localhost localhost. 127.0.0.1 0.0.0.0 [::1] [::]].each do |host|
    it "does not publish a production loopback/wildcard origin #{host}" do
      expect { described_class.validate({ host: host, protocol: "https" }, production: true) }.to raise_error(ArgumentError)
    end
  end

  it "requires secure production protocol" do
    expect { described_class.validate({ host: "payments.example.test", protocol: "http" }, production: true) }
      .to raise_error(ArgumentError)
  end

  [0, 65_536, "invalid"].each do |port|
    it "rejects invalid canonical port #{port}" do
      expect { described_class.validate({ host: "payments.example.test", protocol: "https", port: port }, production: true) }
        .to raise_error(ArgumentError)
    end
  end

  it "installs the parsed canonical options into the application's request-independent URL defaults" do
    expect(Rails.application.default_url_options).to include(
      host: Rails.application.config.action_mailer.default_url_options[:host], protocol: "http"
    )
  end

  describe "production configuration without network or production database boot" do
    class ConfigProbe
      def initialize
        @values = {}
      end

      def method_missing(name, *args)
        if name.to_s.end_with?("=")
          @values[name.to_s.delete_suffix("=").to_sym] = args.first
        else
          @values.key?(name) ? @values[name] : @values[name] = self.class.new
        end
      end

      def respond_to_missing?(*args) = true
    end

    def load_production_config(env:, tasks:)
      context = Object.new
      config = ConfigProbe.new
      context.define_singleton_method(:config) { config }
      application = Object.new
      application.define_singleton_method(:configure) { |&block| context.instance_exec(&block) }
      rails = Module.new
      rails.define_singleton_method(:application) { application }
      source = Rails.root.join("config/environments/production.rb")
      stub_const("Rails", rails)
      stub_const("ENV", env)
      allow(Rake.application).to receive(:top_level_tasks).and_return(tasks)
      load source
      config
    end

    it "uses clearly marked non-deliverable metadata only for dummy-key asset precompilation" do
      config = load_production_config(env: { "SECRET_KEY_BASE_DUMMY" => "1" }, tasks: ["assets:precompile"])
      expect(config.x.canonical_url_build_metadata).to be(true)
      expect(config.action_mailer.default_url_options).to include(host: "assets-build.invalid", protocol: "https")
    end

    it "does not permit the dummy-key shortcut for a runtime or migration boot" do
      expect { load_production_config(env: { "SECRET_KEY_BASE_DUMMY" => "1" }, tasks: ["db:migrate"]) }.to raise_error(KeyError)
    end

    it "does not permit a mixed assets/financial-migration command to use build metadata" do
      expect { load_production_config(env: { "SECRET_KEY_BASE_DUMMY" => "1" }, tasks: ["assets:precompile", "db:migrate"]) }
        .to raise_error(KeyError)
    end

    it "loads an explicitly supplied secure runtime origin without making provider requests" do
      config = load_production_config(env: { "APP_HOST" => "deployment.example.test", "APP_PORT" => "8443" }, tasks: ["environment"])
      expect(config.x.canonical_url_build_metadata).to be(false)
      expect(config.action_mailer.default_url_options).to include(host: "deployment.example.test", protocol: "https", port: 8443)
    end
  end
end
