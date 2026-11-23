# frozen_string_literal: true

#
# This spec tests Page versioning behavior via the shared, content-addressed
# Versionable concern (see spec/models/concerns/versionable_spec.rb for the
# authoritative behavior spec). The bespoke create_version_snapshot! (with
# de-dup/blank guards) and rollback_to_version! have been removed:
#   - #commit_version! is auto-invoked after every save and no-ops when the
#     configuration hash is unchanged.
#   - #restore_as_new! creates a single new head version referencing the
#     chosen version's existing content row (no payload copy, no "Before
#     restore"/"Restored from" pair).
#   - #set_current_version! moves the head pointer only.
#

require "rails_helper"

RSpec.describe Page, "versioning", type: :model do
  let_it_be(:customer) { create(:customer) }
  let(:page)     { create(:page, customer: customer) }

  def bump_configuration!(page, key, value)
    config = JSON.parse(page.configuration)
    config["metadata"][key] = value
    page.configuration = config.to_json
    page.save!
  end

  # ---------------------------------------------------------------------------
  # has_many :page_versions / belongs_to :current_version (provided by Versionable)
  # ---------------------------------------------------------------------------
  describe "has_many :page_versions" do
    it "already holds one version after creation (auto-committed on save)" do
      expect(page.page_versions.count).to eq(1)
    end

    it "destroys versions when the page is destroyed" do
      page # force lazy creation (and its v1) before measuring the change
      expect { page.destroy }.to change(PageVersion, :count).by(-1)
    end
  end

  describe "belongs_to :current_version" do
    it "points at version 1 immediately after creation" do
      expect(page.current_version).to be_present
      expect(page.current_version.version_number).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # #commit_version! (auto-committed on save)
  # ---------------------------------------------------------------------------
  describe "#commit_version! (auto-committed on save)" do
    it "no-ops when the configuration is unchanged (rename creates no version)" do
      expect { page.update!(name: "Renamed Page") }.not_to change { page.page_versions.count }
    end

    it "creates a new PageVersion and advances the head when configuration changes" do
      v1 = page.current_version
      expect { bump_configuration!(page, "custom", "changed") }
        .to change(PageVersion, :count).by(1)
      expect(page.current_version.version_number).to eq(2)
      expect(page.current_version_id).not_to eq(v1.id)
    end

    it "copies the page's current configuration into the version's content" do
      bump_configuration!(page, "custom", "changed")
      # Content rows store a canonicalized (key-sorted) JSON string, so compare
      # semantically rather than byte-for-byte.
      expect(JSON.parse(page.current_version.payload)).to eq(JSON.parse(page.configuration))
    end

    it "sets customer_id on the version from the page" do
      expect(page.current_version.customer_id).to eq(customer.id)
    end

    it "reuses one content row for an identical configuration committed twice" do
      original = page.configuration
      bump_configuration!(page, "custom", "changed")
      page.configuration = original
      page.save!
      expect(PageConfigurationContent.where(customer_id: customer.id).count).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # pruning to MAX_VERSIONS
  # ---------------------------------------------------------------------------
  describe "pruning to MAX_VERSIONS" do
    it "keeps only the latest MAX_VERSIONS versions and GCs orphaned content" do
      stub_const("Versionable::MAX_VERSIONS", 2)
      3.times { |n| bump_configuration!(page, "custom", "rev#{n}") }
      expect(page.page_versions.count).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # #restore_as_new! (replaces the retired rollback_to_version!)
  # ---------------------------------------------------------------------------
  describe "#restore_as_new!" do
    it "creates exactly ONE new head version (no 'Before restore'/'Restored from' pair)" do
      v1 = page.current_version
      bump_configuration!(page, "custom", "changed")

      expect { page.restore_as_new!(v1) }.to change { page.page_versions.count }.by(1)
    end

    it "references the chosen version's existing content row (no new content row)" do
      v1 = page.current_version
      bump_configuration!(page, "custom", "changed")
      content_count = PageConfigurationContent.where(customer_id: customer.id).count

      page.restore_as_new!(v1)

      expect(PageConfigurationContent.where(customer_id: customer.id).count).to eq(content_count)
    end

    it "sets current_version to the restored version and records lineage" do
      v1 = page.current_version
      bump_configuration!(page, "custom", "changed")

      page.restore_as_new!(v1)

      expect(page.current_version.based_on_version_id).to eq(v1.id)
      expect(page.current_version.version_number).to eq(3)
    end

    it "restores the page configuration to the chosen version" do
      v1 = page.current_version
      # Compare semantically: content rows canonicalize (key-sort) the payload,
      # so the in-memory string need not be byte-identical to the original.
      original_config = JSON.parse(page.configuration)
      bump_configuration!(page, "custom", "changed")

      page.restore_as_new!(v1)

      expect(JSON.parse(page.configuration)).to eq(original_config)
      expect(JSON.parse(page.reload.configuration)).to eq(original_config)
    end
  end

  # ---------------------------------------------------------------------------
  # #set_current_version!
  # ---------------------------------------------------------------------------
  describe "#set_current_version!" do
    it "moves the head pointer without creating a version and reloads the configuration" do
      v1 = page.current_version
      original_config = JSON.parse(page.configuration)
      bump_configuration!(page, "custom", "changed")

      expect { page.set_current_version!(v1) }.not_to change { page.page_versions.count }
      expect(page.current_version_id).to eq(v1.id)
      expect(JSON.parse(page.configuration)).to eq(original_config)
    end
  end

  # ---------------------------------------------------------------------------
  # #display_current_version
  # ---------------------------------------------------------------------------
  describe "#display_current_version" do
    it "returns the explicit head when set" do
      bump_configuration!(page, "custom", "v2")
      v2 = page.current_version
      expect(page.display_current_version).to eq(v2)
    end

    it "falls back to the most recent version when no explicit head is set" do
      bump_configuration!(page, "custom", "v2")
      v2 = page.current_version
      page.update_column(:current_version_id, nil)
      page.association(:current_version).reset
      expect(page.display_current_version).to eq(v2)
    end
  end

  # ---------------------------------------------------------------------------
  # multi-tenant content scoping
  # ---------------------------------------------------------------------------
  describe "multi-tenant content scoping" do
    it "does not share content rows across customers" do
      other = create(:customer)
      other_page = create(:page, customer: other)
      expect(page.current_version.content_id).not_to eq(other_page.current_version.content_id)
    end
  end
end
