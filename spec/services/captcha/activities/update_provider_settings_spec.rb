# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::Activities::UpdateProviderSettings do
  let!(:settings) { create(:captcha_provider_settings, access_key_secret: "OLD_SECRET", enabled: false) }

  def update(provider: "aliyun", **params) = described_class.call(provider: provider, params: params)

  it "fails validation and reports the missing access_key_id/scene_id" do
    res = update(access_key_id: "", scene_id: "", access_key_secret: "")
    expect(res.success?).to eq(false)
    expect(res.errors.join(" ")).to match(/access key id|scene id/i)
  end

  it "updates non-secret fields and rotates the secret on non-blank submission" do
    res = update(
      access_key_id: "NEW_KEY", scene_id: "scn-2", access_key_secret: "NEW_SECRET",
      endpoint: "captcha.cn-shanghai.aliyuncs.com", region: "cn-shanghai", enabled: "1"
    )
    expect(res.success?).to eq(true)
    expect(settings.reload).to have_attributes(
      access_key_id: "NEW_KEY", access_key_secret: "NEW_SECRET", enabled: true
    )
    expect(settings.config_value(:scene_id)).to eq("scn-2")
  end

  it "preserves the existing secret when access_key_secret is blank" do
    update(
      access_key_id: "NEW_KEY", scene_id: "scn-2", access_key_secret: "",
      endpoint: "captcha.cn-shanghai.aliyuncs.com", region: "cn-shanghai"
    )
    expect(settings.reload.access_key_secret).to eq("OLD_SECRET")
  end

  it "merges submitted config keys into the JSON config blob without nuking other keys" do
    update(access_key_id: "K", access_key_secret: "S", scene_id: "new-scene")
    expect(settings.reload.config_value(:scene_id)).to eq("new-scene")
    # Pre-existing endpoint/region keys remain
    expect(settings.config_value(:endpoint)).to eq("captcha.cn-shanghai.aliyuncs.com")
    expect(settings.config_value(:region)).to eq("cn-shanghai")
  end

  it "deletes a config key back to its provider default when submitted blank" do
    settings.write_config(endpoint: "custom.endpoint.com")
    settings.save!
    update(access_key_id: "K", access_key_secret: "S", scene_id: "scn", endpoint: "")
    expect(settings.reload.config_value(:endpoint)).to be_nil
  end

  it "creates the provider row on first access via .for_provider" do
    expect {
      described_class.call(provider: "turnstile", params: { access_key_id: "SITE", access_key_secret: "SECRET" })
    }.to change(Captcha::ProviderSettings, :count).by(1)
    expect(Captcha::ProviderSettings.find_by(provider: "turnstile")).to have_attributes(access_key_id: "SITE")
  end

  describe "enabled/activate!/deactivate!" do
    it "activates this provider and clears any other active row when enabled: true" do
      other = create(:captcha_provider_settings, provider: "turnstile", access_key_id: "SK", access_key_secret: "SS", enabled: true)
      update(access_key_id: "K", access_key_secret: "S", scene_id: "scn", enabled: "1")
      expect(settings.reload.enabled).to eq(true)
      expect(other.reload.enabled).to eq(false)
    end

    it "deactivates the provider when enabled: false is submitted" do
      settings.update!(enabled: true)
      update(access_key_id: "K", access_key_secret: "S", scene_id: "scn", enabled: "0")
      expect(settings.reload.enabled).to eq(false)
    end

    it "leaves the current enabled state unchanged when 'enabled' key is not submitted at all" do
      settings.update!(enabled: true)
      update(access_key_id: "K", access_key_secret: "S", scene_id: "scn")
      expect(settings.reload.enabled).to eq(true)
    end

    it "switches the live vendor from active_assignee without requiring the current tab's credentials" do
      settings.update!(enabled: true)
      res = described_class.call(provider: "aliyun", params: { active_assignee: "turnstile" })
      expect(res.success?).to eq(true)
      expect(settings.reload.enabled).to eq(false)
      expect(Captcha::ProviderSettings.find_by!(provider: "turnstile").enabled).to eq(true)
    end

    it "clears the live vendor when active_assignee is blank" do
      settings.update!(enabled: true)
      res = described_class.call(provider: "aliyun", params: { active_assignee: "" })
      expect(res.success?).to eq(true)
      expect(settings.reload.enabled).to eq(false)
    end
  end

  describe "fail_policy" do
    it "updates fail_policy when submitted" do
      update(access_key_id: "K", access_key_secret: "S", scene_id: "scn", fail_policy: "closed")
      expect(settings.reload.fail_policy).to eq("closed")
    end

    it "defaults to 'open' when fail_policy is submitted blank" do
      settings.update!(fail_policy: "closed")
      update(access_key_id: "K", access_key_secret: "S", scene_id: "scn", fail_policy: "")
      expect(settings.reload.fail_policy).to eq("open")
    end

    it "rejects an invalid fail_policy via the contract" do
      res = update(access_key_id: "K", access_key_secret: "S", scene_id: "scn", fail_policy: "sideways")
      expect(res.success?).to eq(false)
    end
  end

  describe "score_threshold" do
    it "updates score_threshold when submitted" do
      update(access_key_id: "K", access_key_secret: "S", scene_id: "scn", score_threshold: "0.7")
      expect(settings.reload.score_threshold.to_f).to eq(0.7)
    end
  end

  it "returns the model and errors on the Result even on failure" do
    res = update(access_key_id: "", scene_id: "", access_key_secret: "")
    expect(res.model).to eq(settings)
    expect(res.errors).not_to be_empty
  end

  it "does not persist a failed update" do
    settings.update!(access_key_id: "ORIGINAL")
    update(access_key_id: "", scene_id: "", access_key_secret: "")
    expect(settings.reload.access_key_id).to eq("ORIGINAL")
  end
end
