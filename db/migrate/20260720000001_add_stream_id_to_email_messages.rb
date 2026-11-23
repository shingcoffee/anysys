# frozen_string_literal: true

class AddStreamIdToEmailMessages < ActiveRecord::Migration[8.1]
  def change
    add_reference :email_messages, :email_stream, foreign_key: true, index: true
  end
end
