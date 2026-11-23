# frozen_string_literal: true

module Admin
  class EntityDefinitionsController < ApplicationController
    include Oauth::BearerAuthenticatable

    def index
      _signal, (ctx, *) = EntityDefinitions::List.call({})
      render json: ctx[:json]
    end
  end
end
