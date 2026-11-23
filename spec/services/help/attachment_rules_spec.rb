# frozen_string_literal: true

require "rails_helper"

RSpec.describe Help::AttachmentRules do
  it "exposes a locale-aware size label" do
    expect(described_class.size_label).to eq("5MB")
    I18n.with_locale(:"zh-CN") { expect(described_class.size_label).to eq("5MB") }
  end

  it "builds Stimulus data from the shared limits" do
    data = described_class.stimulus_data(accept: described_class.image_accept)

    expect(data[:controller]).to eq("help-attachments")
    expect(data[:help_attachments_max_files_value]).to eq(described_class::MAX_FILES)
    expect(data[:help_attachments_size_label_value]).to eq("5MB")
    expect(data[:help_attachments_remove_mark_value]).to eq("×")
  end
end
