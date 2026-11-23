class CreateAliyunCaptchaPlatformSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :aliyun_captcha_platform_settings do |t|
      t.string  :access_key_id
      t.text    :access_key_secret           # AR encrypts at rest
      t.string  :scene_id
      t.string  :endpoint, null: false, default: "captcha.cn-shanghai.aliyuncs.com"
      t.string  :region,   null: false, default: "cn-shanghai"
      t.boolean :enabled,  null: false, default: false
      t.datetime :last_health_check_at
      t.string   :last_health_check_status   # "ok" | "configuration_error" | "unreachable"
      t.string   :last_health_check_message
      t.timestamps
    end
  end
end
