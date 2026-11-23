class RenameAliyunCaptchaToCaptchaProviderSettings < ActiveRecord::Migration[8.1]
  def up
    rename_table :aliyun_captcha_platform_settings, :captcha_provider_settings

    add_column :captcha_provider_settings, :provider, :string
    add_column :captcha_provider_settings, :config,   :text

    # Backfill: existing rows are Aliyun. Move vendor-specific fields into the
    # JSON config blob so the table can hold rows for any vendor.
    execute <<~SQL.squish
      UPDATE captcha_provider_settings
         SET provider = 'aliyun',
             config = json_object(
               'scene_id', scene_id,
               'endpoint', endpoint,
               'region',   region
             )
    SQL

    change_column_null :captcha_provider_settings, :provider, false
    add_index :captcha_provider_settings, :provider, unique: true

    remove_column :captcha_provider_settings, :scene_id
    remove_column :captcha_provider_settings, :endpoint
    remove_column :captcha_provider_settings, :region

    # Promote the FeatureModule key from vendor-specific to vendor-agnostic.
    # Drop any pre-existing 'captcha' row (auto-seeded by app boot before this
    # migration ran) so the rename below doesn't trip the UNIQUE(key) index.
    execute <<~SQL.squish
      DELETE FROM feature_modules
       WHERE key = 'captcha'
         AND id NOT IN (SELECT feature_module_id FROM customer_feature_modules)
    SQL

    execute <<~SQL.squish
      UPDATE feature_modules
         SET key  = 'captcha',
             name = 'Captcha'
       WHERE key = 'aliyun_captcha'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE feature_modules
         SET key  = 'aliyun_captcha',
             name = 'Aliyun Captcha'
       WHERE key = 'captcha'
    SQL

    add_column :captcha_provider_settings, :scene_id, :string
    add_column :captcha_provider_settings, :endpoint, :string, null: false, default: "captcha.cn-shanghai.aliyuncs.com"
    add_column :captcha_provider_settings, :region,   :string, null: false, default: "cn-shanghai"

    execute <<~SQL.squish
      UPDATE captcha_provider_settings
         SET scene_id = json_extract(config, '$.scene_id'),
             endpoint = COALESCE(json_extract(config, '$.endpoint'), 'captcha.cn-shanghai.aliyuncs.com'),
             region   = COALESCE(json_extract(config, '$.region'),   'cn-shanghai')
    SQL

    remove_index  :captcha_provider_settings, :provider
    remove_column :captcha_provider_settings, :provider
    remove_column :captcha_provider_settings, :config

    rename_table :captcha_provider_settings, :aliyun_captcha_platform_settings
  end
end
