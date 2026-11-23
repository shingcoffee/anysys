# frozen_string_literal: true

class AddCrudTypeToFlowcharts < ActiveRecord::Migration[8.1]
  def change
    # Optional classification flagging which CRUD operation (create/read/
    # update/delete) of its bound entity a flowchart represents. Nullable —
    # a flowchart may be left unclassified.
    add_column :flowcharts, :crud_type, :string
  end
end
