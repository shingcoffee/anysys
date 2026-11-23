# frozen_string_literal: true

# Lifts the one-thread-per-user ceiling: an admin keeps a list of named
# conversations instead of destroying the only thread to start over.
#
# The old unique (customer_id, user_id) index is what enforced the single
# thread, so it goes. `last_active_at` is denormalized rather than derived from
# the newest message because the sidebar orders by it on every page load.
class AddConversationHistoryToAiAssistant < ActiveRecord::Migration[8.1]
  def up
    add_column :ai_assistant_conversations, :title, :string
    add_column :ai_assistant_conversations, :archived_at, :datetime
    add_column :ai_assistant_conversations, :last_active_at, :datetime

    execute(<<~SQL.squish)
      UPDATE ai_assistant_conversations SET last_active_at = updated_at WHERE last_active_at IS NULL
    SQL

    # Non-null keeps the sidebar's ORDER BY free of a NULLS LAST clause, whose
    # support varies by SQLite build.
    change_column_null :ai_assistant_conversations, :last_active_at, false

    remove_index :ai_assistant_conversations,
                 column: %i[customer_id user_id],
                 name: "idx_ai_assistant_conversations_on_customer_and_user"

    add_index :ai_assistant_conversations,
              %i[customer_id user_id archived_at last_active_at],
              name: "idx_ai_assistant_conversations_on_owner_and_activity"
  end

  def down
    remove_index :ai_assistant_conversations,
                 name: "idx_ai_assistant_conversations_on_owner_and_activity"

    # Restoring a unique index requires collapsing the history back to one row
    # per owner. Keep the most recently active thread and drop the rest.
    execute(<<~SQL.squish)
      DELETE FROM ai_assistant_conversations
      WHERE id NOT IN (
        SELECT MAX(id) FROM ai_assistant_conversations GROUP BY customer_id, user_id
      )
    SQL

    add_index :ai_assistant_conversations,
              %i[customer_id user_id],
              unique: true,
              name: "idx_ai_assistant_conversations_on_customer_and_user"

    remove_column :ai_assistant_conversations, :last_active_at
    remove_column :ai_assistant_conversations, :archived_at
    remove_column :ai_assistant_conversations, :title
  end
end
