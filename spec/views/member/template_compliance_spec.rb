# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member views template compliance" do
  views_root = Rails.root.join("app/views/member")

  # Non-partial .html.erb files (skip filenames starting with _).
  # Also skip any directory segment matching the Rails *_mailer convention —
  # those are email templates, not routed pages.
  #
  # Documented exemption: member/pages/show renders a self-contained page-builder
  # PageComponent (@content) directly at the page's own form width, intentionally
  # NOT through Member::PageLayoutComponent (see that view's header comment) — it
  # borrows only the page's form width for alignment, not the member card chrome.
  exempt = ["app/views/member/pages/show.html.erb"].freeze
  view_files = Dir.glob(views_root.join("**/*.html.erb")).reject do |path|
    basename = File.basename(path)
    segments = Pathname.new(path).each_filename.to_a
    rel = Pathname.new(path).relative_path_from(Rails.root).to_s
    basename.start_with?("_") || segments.any? { |s| s.end_with?("_mailer") } ||
      exempt.include?(rel)
  end

  it "discovers at least one member view" do
    expect(view_files).not_to be_empty
  end

  view_files.each do |path|
    rel = Pathname.new(path).relative_path_from(Rails.root).to_s

    it "#{rel} renders through Member::PageLayoutComponent" do
      contents = File.read(path)
      expect(contents).to include("Member::PageLayoutComponent"),
        "Expected #{rel} to render through Member::PageLayoutComponent (unified page template). " \
        "Found content:\n#{contents[0, 300]}"
    end
  end
end
