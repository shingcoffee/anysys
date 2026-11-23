# frozen_string_literal: true

class BackfillEmailMessageStreams < ActiveRecord::Migration[8.1]
  def up
    kind_map = {
      "transactional" => "transactional",
      "marketing" => "campaign",
      "automated" => "transactional"
    }

    Emails::Stream.find_each do |stream|
      Emails::Message
        .where(customer_id: stream.customer_id, message_type: kind_map.fetch(stream.kind, "transactional"))
        .where(email_stream_id: nil)
        .update_all(email_stream_id: stream.id)
    end
  end

  def down
    Emails::Message.update_all(email_stream_id: nil)
  end
end
