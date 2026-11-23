class MarkExistingJunctionEntities < ActiveRecord::Migration[8.1]
  def up
    # Mark entities with junction entity descriptions as junction entities
    count = Entity.unscoped
                  .where("description LIKE ?", "Junction entity linking % and %")
                  .update_all(is_junction_entity: true)
    puts "Marked #{count} existing junction entities"
  end

  def down
    # Reset all junction entity flags
    Entity.unscoped.where(is_junction_entity: true).update_all(is_junction_entity: false)
  end
end
