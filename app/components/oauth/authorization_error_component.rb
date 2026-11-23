# frozen_string_literal: true

module Oauth
  class AuthorizationErrorComponent < ApplicationComponent
    def initialize(error_description:)
      @error_description = error_description
    end

    attr_reader :error_description
  end
end
