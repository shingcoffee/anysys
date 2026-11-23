# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Markdown do
  it "renders emphasis, code, lists, and links" do
    html = described_class.render("**bold** and *em* and `code`\n\n- one\n- two\n\n[docs](https://example.com)")
    expect(html).to include("<strong>bold</strong>")
    expect(html).to include("<em>em</em>")
    expect(html).to include("<code>code</code>")
    expect(html).to include("<ul>")
    expect(html).to include("<li>one</li>")
    expect(html).to include('<a href="https://example.com">docs</a>')
  end

  it "renders fenced code and ordered lists" do
    html = described_class.render("```\nputs 1\n```\n\n1. alpha\n2. beta")
    expect(html).to include("<pre><code>puts 1</code></pre>")
    expect(html).to include("<ol>")
    expect(html).to include("<li>alpha</li>")
  end

  it "splits a chunk into a paragraph, a list, and a heading line by line" do
    html = described_class.render("### Summary\nHere is what I built:\n- Student\n- Course\nAll set.")
    expect(html.delete("\n")).to eq(
      "<p><strong>Summary</strong></p><p>Here is what I built:</p><ul><li>Student</li><li>Course</li></ul><p>All set.</p>"
    )
  end

  describe ".compose" do
    it "puts the prose first and the platform notes after it as a list" do
      text = described_class.compose("Built the system.", ["Created: Student, Course.", " ", "Created bridge.\n"])
      expect(text).to eq("Built the system.\n\n- Created: Student, Course.\n- Created bridge.")
      expect(described_class.render(text).delete("\n")).to eq(
        "<p>Built the system.</p><ul><li>Created: Student, Course.</li><li>Created bridge.</li></ul>"
      )
    end

    it "keeps a lone note without prose as a plain sentence" do
      expect(described_class.compose(nil, ["Updated: Student."])).to eq("Updated: Student.")
      expect(described_class.compose(" ", ["A.", "B."])).to eq("- A.\n- B.")
    end

    it "returns the stripped prose when there are no notes" do
      expect(described_class.compose("  Hi.  ", [])).to eq("Hi.")
      expect(described_class.compose(nil)).to eq("")
    end
  end

  it "joins non-blank parts as paragraphs" do
    expect(described_class.paragraphs(" One. ", nil, "", ["Two."])).to eq("One.\n\nTwo.")
  end

  it "escapes HTML and drops javascript URLs" do
    html = described_class.render("<script>alert(1)</script> [x](javascript:alert(1))")
    expect(html).not_to include("<script>")
    expect(html).to include("&lt;script&gt;")
    expect(html).not_to include('href="javascript:')
  end
end
