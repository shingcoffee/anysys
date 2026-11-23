# frozen_string_literal: true

class HomeController < ApplicationController
  include Authentication::FinishesSignIn

  layout "auth"

  def index
    if user_signed_in?
      redirect_to default_signed_in_path_for(current_user)
      return
    end

    @user = Authentication::User.new
  end
end
