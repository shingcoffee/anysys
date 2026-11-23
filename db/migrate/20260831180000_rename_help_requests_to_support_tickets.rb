# frozen_string_literal: true

class RenameHelpRequestsToSupportTickets < ActiveRecord::Migration[8.1]
  def change
    rename_table :help_requests, :support_tickets
    rename_table :help_request_messages, :support_ticket_messages
    rename_table :help_request_reads, :support_ticket_reads

    rename_column :support_ticket_messages, :help_request_id, :support_ticket_id
    rename_column :support_ticket_reads, :help_request_id, :support_ticket_id

    # Default-named indexes are renamed by Rails with the table/column.
    # Only the custom unique index needs an explicit rename.
    rename_index :support_ticket_reads, "idx_help_request_reads_unique", "idx_support_ticket_reads_unique"

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE active_storage_attachments
          SET record_type = 'SupportTicketMessage'
          WHERE record_type = 'HelpRequestMessage'
        SQL
      end
      dir.down do
        execute <<~SQL.squish
          UPDATE active_storage_attachments
          SET record_type = 'HelpRequestMessage'
          WHERE record_type = 'SupportTicketMessage'
        SQL
      end
    end
  end
end
