# frozen_string_literal: true

# The base AR model class name an entity extends. Only meaningful when
# category == :extension; NULL for :plain and :bridge entities. This is live
# structural data (not part of the versioned definition payload), same as
# `category`.
class AddExtendedModelToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :extended_model, :string
  end
end
