# frozen_string_literal: true

module Emails
  # Builds the interpolation hash for campaign sends from a recipient User
  # and a curated set of associations. Mirrors FieldCatalog's exposed data so
  # tokens offered in the editor resolve at send time.
  class VariableContext
    def self.for(user:)
      new(user).to_h
    end

    def initialize(user)
      @user = user
    end

    def to_h
      {
        authentication_user: public_user_attributes,
        customer:            @user.customer&.attributes&.symbolize_keys || {},
        unsubscribe_url:     unsubscribe_url
      }
    end

    private

    def public_user_attributes
      @user.attributes.symbolize_keys.except(*Authentication::User::SENSITIVE_COLUMNS.map(&:to_sym))
    end

    def unsubscribe_url
      Emails::SendActivities::SendActivityUnsubscribe.url_for(@user)
    end
  end
end
