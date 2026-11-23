# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Sanitize do
  describe ".apply" do
    it "strips tags, escapes HTML and deletes null bytes" do
      expect(described_class.apply("<p>hi</p>", sanitizer: "strip_tags")).to eq("hi")
      expect(described_class.apply("<b>x</b>", sanitizer: "escape_html")).to include("&lt;b&gt;")
      expect(described_class.apply("a\u0000b", sanitizer: "strip_tags", remove_null_bytes: true)).to eq("ab")
    end

    it "trims whitespace and fails when overflow is fail" do
      expect(described_class.apply("  hi  ", sanitizer: "strip_tags", trim_whitespace: true)).to eq("hi")
      expect {
        described_class.apply("hello world", sanitizer: "strip_tags", max_length: 4, on_overflow: "fail")
      }.to raise_error(described_class::Error, /max length/)
    end
  end

  describe ".html" do
    it "prunes unsafe markup by default" do
      result = described_class.html("<p>ok</p><script>alert(1)</script>")
      expect(result).to include("ok")
      expect(result).not_to include("script")
    end

    it "accepts a custom Loofah scrub mode" do
      result = described_class.html("<b>bold</b><script>x</script>", mode: :escape)
      expect(result).to include("&lt;script&gt;")
      expect(result).to include("<b>bold</b>")
    end

    it "coerces input with to_s" do
      expect(described_class.html(:symbol)).to eq("symbol")
    end

    it "does not swallow unexpected Loofah failures" do
      allow(Loofah).to receive(:fragment).and_raise(StandardError, "scrub failed")

      expect { described_class.html("<p>x</p>") }
        .to raise_error(StandardError, "scrub failed")
    end

    it "rejects unsupported scrub modes before calling Loofah" do
      expect { described_class.html("<p>x</p>", mode: :unknown) }
        .to raise_error(FlowchartRuntime::Sanitize::Error, "unsupported scrub mode")
    end
  end

  describe ".strip_tags" do
    it "removes HTML tags" do
      expect(described_class.strip_tags("<p>hello <b>world</b></p>")).to eq("hello world")
    end

    it "coerces input with to_s" do
      expect(described_class.strip_tags(123)).to eq("123")
    end

    it "does not swallow unexpected sanitizer failures" do
      sanitizer = instance_double(Rails::Html::FullSanitizer)
      allow(Rails::Html::FullSanitizer).to receive(:new).and_return(sanitizer)
      allow(sanitizer).to receive(:sanitize).and_raise(StandardError, "sanitize failed")

      expect { described_class.strip_tags("<p>x</p>") }
        .to raise_error(StandardError, "sanitize failed")
    end
  end
end
