class AddUniqueIndexToSharedConstants < ActiveRecord::Migration[8.1]
  def change
    # Shared constants (customer_id IS NULL) must have globally unique names.
    # Customer-specific names are already covered by the partial unique index
    # on [customer_id, name]. This closes the race left by the model-level
    # uniqueness validation for shared rows.
    add_index :constants, :name,
              unique: true,
              where: "customer_id IS NULL",
              name: "index_constants_on_name_for_shared"
  end
end
