# frozen_string_literal: true

class MakeMemberSurfaceSettingsEnabledNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :member_surface_settings, :enabled, true
    change_column_default :member_surface_settings, :enabled, from: true, to: nil
  end
end
