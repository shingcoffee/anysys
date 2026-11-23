# frozen_string_literal: true

require "rails_helper"
require "open3"

RSpec.describe DeveloperDocs::Highlighter do
  it "renders inline and fenced code after real Rails reloads, including retained formatter callbacks" do
    # The test environment disables reloading. A development subprocess exercises
    # Zeitwerk unloading without invalidating the parent suite's application classes.
    script = <<~'RUBY'
      markdown = <<~MD
        Inline `<strong>` stays escaped.

        ```ruby
        class Example
          VALUE = "<tag>"
        end
        ```
      MD

      render = lambda do
        DeveloperDocs::Renderer.call(
          markdown,
          link_resolver: ->(slug) { "/docs/#{slug}" },
          labels: { "attention" => I18n.t("developer_docs.callouts.attention"), "note" => I18n.t("developer_docs.callouts.note") },
          anchor_label: I18n.t("developer_docs.anchor")
        ).html
      end

      check_html = lambda do |html|
        %w[text-violet-300 overflow-x-auto &lt;tag&gt; &lt;strong&gt;].each do |expected|
          raise "rendered code missing #{expected}: #{html}" unless html.include?(expected)
        end
        raise "unescaped code" if html.include?("<tag>") || html.include?("<strong>")
      end

      raise "development reloading is disabled" unless Rails.application.config.enable_reloading
      check_html.call(render.call)
      retained_formatters = []

      2.times do
        previous_highlighter = DeveloperDocs::Highlighter
        retained_formatters << Kramdown::Converter.syntax_highlighter(:tailwind_rouge)
        Rails.application.reloader.reload!
        raise "Rails did not unload the highlighter" if DeveloperDocs::Highlighter.equal?(previous_highlighter)

        # A converter may already hold the callback from before the reload.
        retained_formatters.each do |formatter|
          inline = formatter.call(nil, "<tag>", "text", :span, {})
          raise "stale inline callback failed" unless inline == "&lt;tag&gt;"
          block = formatter.call(nil, "<tag>", "text", :block, {})
          raise "stale block callback failed" unless block.include?("<pre") && block.include?("&lt;tag&gt;")
        end

        check_html.call(render.call)
        unless Kramdown::Converter.syntax_highlighter(:tailwind_rouge).equal?(DeveloperDocs::Highlighter::Formatter)
          raise "Kramdown retained a stale formatter after rendering"
        end
      end

      puts "reload-safe: inline and fenced code survived two Rails reloads"
    RUBY

    stdout, stderr, status = Open3.capture3(
      { "RAILS_ENV" => "development" },
      RbConfig.ruby, Rails.root.join("bin/rails").to_s, "runner", "-e", "development", script,
      chdir: Rails.root.to_s
    )

    expect(status).to be_success, "Rails reload regression failed:\n#{stdout}\n#{stderr}"
    expect(stdout).to include("reload-safe: inline and fenced code survived two Rails reloads")
  end
end
