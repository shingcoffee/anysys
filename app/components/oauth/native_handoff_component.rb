# frozen_string_literal: true

module Oauth
  class NativeHandoffComponent < ApplicationComponent
    def initialize(redirect_uri:)
      @redirect_uri = redirect_uri
    end

    attr_reader :redirect_uri
  end
end
