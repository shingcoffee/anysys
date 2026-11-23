# frozen_string_literal: true

module Member
  class ProfilesController < BaseController
    def show
    end

    def edit
      @contract = Member::Profiles::UpdateContract.new(current_user)
    end

    def update
      @contract = Member::Profiles::UpdateContract.new(current_user)

      if @contract.validate(profile_params) && @contract.save
        redirect_to "/#{current_user.customer_id}/member/profile",
                    notice: t("member.flash.profiles.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def profile_params
      raw = params[:member_profiles_update_contract]
      raise ActionController::ParameterMissing, :member_profiles_update_contract unless raw.is_a?(ActionController::Parameters)

      raw.permit(:first_name, :last_name, :email, :current_password)
    end
  end
end
