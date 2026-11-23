# frozen_string_literal: true

require "rails_helper"

RSpec.describe People::Contracts::Link do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }

  before do
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
  end

  def person_entity(name: "Student")
    create(:entity, customer: customer, name: name, extended_model: person_model)
  end

  def validate(entry, user_id)
    form = described_class.new(entry)
    form.validate("user_id" => user_id)
    form
  end

  it "accepts an active same-tenant user on an unlinked person entry" do
    entry = create(:entity_entry, entity: person_entity, customer: customer)
    user = create(:user, customer: customer)

    expect(validate(entry, user.id)).to be_valid
  end

  it "rejects a non-person entity" do
    entity = create(:entity, customer: customer)
    entry = create(:entity_entry, entity: entity, customer: customer)
    user = create(:user, customer: customer)

    expect(validate(entry, user.id).errors[:base]).to include(I18n.t("people.errors.not_a_person"))
  end

  it "uses one generic message for a missing, other-tenant, or inactive user" do
    entry = create(:entity_entry, entity: person_entity, customer: customer)
    foreign = create(:user, customer: other_customer)
    inactive = create(:user, :inactive, customer: customer)
    message = I18n.t("people.errors.user_unavailable")

    [nil, 0, 999_999_999, foreign.id, inactive.id].each do |user_id|
      expect(validate(entry, user_id).errors[:base]).to include(message)
    end
  end

  it "rejects an entry that is already linked" do
    user = create(:user, customer: customer)
    entry = create(:entity_entry, entity: person_entity, customer: customer, user: user)

    expect(validate(entry, create(:user, customer: customer).id).errors[:base])
      .to include(I18n.t("people.errors.already_linked"))
  end

  it "rejects a user already linked to another entry of the same entity" do
    entity = person_entity
    user = create(:user, customer: customer)
    create(:entity_entry, entity: entity, customer: customer, user: user)
    entry = create(:entity_entry, entity: entity, customer: customer)

    expect(validate(entry, user.id).errors[:base]).to include(I18n.t("people.errors.user_already_linked"))
  end

  it "allows the same user to be linked on a different person entity" do
    user = create(:user, customer: customer)
    create(:entity_entry, entity: person_entity(name: "Student"), customer: customer, user: user)
    other = create(:entity_entry, entity: person_entity(name: "Volunteer"), customer: customer)

    expect(validate(other, user.id)).to be_valid
  end

  it "keeps identical keys and interpolation variables in en and zh-CN" do
    en = I18n.t("people.errors", locale: :en)
    zh = I18n.t("people.errors", locale: :"zh-CN")
    expect(zh.keys).to match_array(en.keys)
    en.each do |key, value|
      en_vars = value.to_s.scan(/%\{(\w+)\}/).flatten
      zh_vars = zh.fetch(key).to_s.scan(/%\{(\w+)\}/).flatten
      expect(zh_vars).to match_array(en_vars)
    end
  end
end
