# frozen_string_literal: true

module Authentication
  # Array/string `user[]=` POSTs used to TypeError on `.permit` and `dig(:email)`.
  module PermitsUserParams
    extend ActiveSupport::Concern

    private

    def permitted_user_params(*keys)
      raw = params[:user]
      return ActionController::Parameters.new unless raw.is_a?(ActionController::Parameters)

      raw.permit(*keys)
    end
  end
end
