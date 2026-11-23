# frozen_string_literal: true

class AddListTypeAndSegmentIdToEmailLists < ActiveRecord::Migration[8.1]
  def up
    add_column :email_lists, :list_type, :string, null: false, default: "dynamic"
    add_reference :email_lists, :email_segment, foreign_key: true, index: true

    migrate_legacy_lists_to_segments
  end

  def down
    remove_reference :email_lists, :email_segment, foreign_key: true, index: true
    remove_column :email_lists, :list_type
  end

  private

  def migrate_legacy_lists_to_segments
    Emails::Audience::List.where(email_segment_id: nil).find_each do |list|
      next if list.segment_rules.blank?

      segment = Emails::Audience::Segment.create!(
        customer_id: list.customer_id,
        name: "#{list.name} (auto)",
        rules: list.segment_rules
      )
      list.update!(email_segment_id: segment.id)
    end
  end
end
