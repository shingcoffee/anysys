# frozen_string_literal: true

require "rails_helper"

RSpec.describe Listable do
  let(:controller_class) do
    Class.new do
      include Listable
      attr_accessor :params
    end
  end
  let(:instance) { controller_class.new }
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }
  let!(:a) { create(:page, customer: customer, entity: entity, name: "Alpha") }
  let!(:b) { create(:page, customer: customer, entity: entity, name: "Beta") }
  let(:columns) { [{ key: :name, label: "Name", sortable: true, searchable: true }] }
  let(:scope)   { Page.for_customer(customer.id) }

  it "applies search, sort, and pagination and returns a structured result" do
    instance.params = ActionController::Parameters.new(q: "al", sort: "name", dir: "asc")
    result = instance.listable(scope, columns: columns)
    expect(result[:rows].map(&:name)).to eq(["Alpha"])
    expect(result[:pagination][:total]).to eq(1)
  end

  it "forwards filters to the resolver" do
    instance.params = ActionController::Parameters.new(name: "Beta")
    result = instance.listable(
      scope,
      columns: columns,
      filters: [{ key: :name, column: :name }]
    )
    expect(result[:rows].map(&:name)).to eq(["Beta"])
  end
end
