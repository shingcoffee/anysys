# frozen_string_literal: true

class AddDisplayLabelToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :display_label, :string, null: false, default: ""

    reversible do |dir|
      dir.up do
        # Backfill existing entities to use their internal name as the display label
        execute("UPDATE entities SET display_label = name WHERE display_label = ''")
      end
    end
  end
end
