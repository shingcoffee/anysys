# frozen_string_literal: true

# Several specs `require "webmock/rspec"`, which registers a suite-wide
# `before(:suite) { WebMock.enable! }` hook. Once enabled, WebMock's default
# blocks every real HTTP connection for the ENTIRE suite — including the
# loopback request Capybara/Selenium makes to its own test server
# (GET http://127.0.0.1:<port>/__identify__). That breaks otherwise-unrelated
# system specs whenever the full suite runs.
#
# Requiring webmock/rspec here (once, at support-load time) and allowing
# localhost keeps external-request stubbing intact while letting the Capybara
# server, Selenium, and chromedriver talk over loopback.
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)
