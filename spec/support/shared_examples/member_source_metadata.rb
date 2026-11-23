# frozen_string_literal: true

# Class-level identity shared by Member::Sources::* specs.
#
#   it_behaves_like "member source metadata",
#     key: :modules, editable: true, position: 10
RSpec.shared_examples "member source metadata" do |key:, editable:, position:|
  it "declares source metadata" do
    expect(described_class.key).to eq(key)
    expect(described_class.editable?).to eq(editable)
    expect(described_class.position).to eq(position)
  end
end
