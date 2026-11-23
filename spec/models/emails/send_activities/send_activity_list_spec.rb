# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::SendActivityList, type: :model do
  describe "validations" do
    it "rejects the same email list twice for one send activity" do
      activity = create(:email_send_activity)
      list = activity.email_lists.first

      duplicate = described_class.new(send_activity: activity, email_list: list)

      expect(duplicate).not_to be_valid
    end

    it "rejects a list from another customer" do
      activity = create(:email_send_activity)
      foreign_list = create(:email_list, customer: create(:customer))

      join = described_class.new(send_activity: activity, email_list: foreign_list)

      expect(join).not_to be_valid
      expect(join.errors[:email_list]).to include(
        I18n.t("admin_modules.errors.validations.cross_tenant_association")
      )
    end

    it "rejects creating an 11th list join for one send activity" do
      customer = create(:customer)
      lists = Array.new(Emails::SendActivities::SendActivity::MAX_EMAIL_LISTS) {
        create(:email_list, customer: customer)
      }
      activity = create(:email_send_activity, customer: customer, email_lists: lists)
      extra = create(:email_list, customer: customer)

      join = described_class.new(send_activity: activity, email_list: extra)

      expect(join).not_to be_valid
      expect(join.errors[:email_list]).to include(
        I18n.t(
          "admin_modules.emails.send_activities.errors.lists_too_many",
          max: Emails::SendActivities::SendActivity::MAX_EMAIL_LISTS
        )
      )
    end
  end
end
