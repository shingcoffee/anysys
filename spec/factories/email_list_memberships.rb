# frozen_string_literal: true

FactoryBot.define do
  factory :email_list_membership, class: "Emails::Audience::ListMembership" do
    association :email_list, factory: :email_list
    association :user, factory: :user
  end
end
