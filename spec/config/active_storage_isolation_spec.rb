# frozen_string_literal: true

require "rails_helper"
require "erb"
require "yaml"
require "tmpdir"

RSpec.describe "Active Storage test isolation" do
  def test_configuration(worker:, root: nil)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("TEST_ENV_NUMBER").and_return(worker)
    allow(ENV).to receive(:[]).with("ACTIVE_STORAGE_ROOT").and_return(root)
    rendered = ERB.new(File.read(Rails.root.join("config/storage.yml"))).result
    YAML.safe_load(rendered).fetch("test")
  end

  it "partitions parallel workers into sibling roots, including the blank first worker" do
    first = test_configuration(worker: "").fetch("root")
    second = test_configuration(worker: "2").fetch("root")

    expect(first).to eq(Rails.root.join("tmp/storage").to_s)
    expect(second).to eq(Rails.root.join("tmp/storage2").to_s)
    expect(File.dirname(first)).to eq(File.dirname(second))
    expect(second).not_to start_with("#{first}/")
  end

  it "partitions an explicit root prefix and ignores blank overrides" do
    root = Rails.root.join("tmp/storage-website-verify").to_s
    expect(test_configuration(worker: "", root: root).fetch("root")).to eq(root)
    expect(test_configuration(worker: "2", root: root).fetch("root")).to eq("#{root}2")
    expect(test_configuration(worker: "", root: "#{root}/").fetch("root")).to eq(root)
    expect(test_configuration(worker: "2", root: "#{root}/").fetch("root")).to eq("#{root}2")
    expect(test_configuration(worker: "2", root: "").fetch("root")).to eq(Rails.root.join("tmp/storage2").to_s)
  end

  it "keeps real uploaded bytes in one worker when another clears its own storage directory" do
    Dir.mktmpdir("active-storage-isolation", Rails.root.join("tmp")) do |directory|
      first = ActiveStorage::Service::DiskService.new(root: File.join(directory, "storage"))
      second = ActiveStorage::Service::DiskService.new(root: File.join(directory, "storage2"))
      key = "same-blob-key-for-two-isolated-workers"
      bytes = File.binread(Rails.root.join("spec/fixtures/files/test.png"))
      checksum = Digest::MD5.base64digest(bytes)
      first.upload(key, StringIO.new(bytes), checksum: checksum)
      second.upload(key, StringIO.new(bytes), checksum: checksum)

      # Only this test's newly allocated second-worker directory is removed.
      # An explicitly configured root or another process's files are untouched.
      FileUtils.remove_entry(File.join(directory, "storage2"))

      expect(second.exist?(key)).to be(false)
      expect(first.download(key)).to eq(bytes)
    end
  end
end
