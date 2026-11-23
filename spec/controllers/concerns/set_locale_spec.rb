# frozen_string_literal: true

require "rails_helper"

# Exercises the locale resolution precedence directly against the concern via
# an anonymous controller, independent of the rest of the ApplicationController
# stack (auth, tenant, MFA).
RSpec.describe SetLocale, type: :controller do
  controller(ActionController::Base) do
    include SetLocale

    # Stub current_user so the from_current_user branch can be tested.
    attr_writer :stub_user

    def current_user
      @stub_user
    end

    def index
      render plain: I18n.locale.to_s
    end
  end

  before do
    routes.draw { get "index" => "anonymous#index" }
  end

  def stub_user_with(locale)
    controller.stub_user = double("user", locale: locale)
  end

  def stub_customer_with(locale)
    allow(Current).to receive(:customer).and_return(double("customer", locale: locale))
  end

  it "defaults to :en when nothing is supplied" do
    get :index
    expect(response.body).to eq("en")
  end

  it "honours params[:locale] above everything else" do
    stub_customer_with("en")
    stub_user_with("en")
    request.cookies[:locale] = "en"
    get :index, params: { locale: "zh-CN" }
    expect(response.body).to eq("zh-CN")
  end

  it "uses the tenant default when the user has expressed no choice, above Accept-Language" do
    stub_customer_with("zh-CN")
    request.headers["Accept-Language"] = "en-US,en;q=0.9"
    get :index
    expect(response.body).to eq("zh-CN")
  end

  it "lets a user preference override the tenant default" do
    stub_customer_with("en")
    stub_user_with("zh-CN")
    get :index
    expect(response.body).to eq("zh-CN")
  end

  it "lets the cookie override the tenant default" do
    stub_customer_with("en")
    request.cookies[:locale] = "zh-CN"
    get :index
    expect(response.body).to eq("zh-CN")
  end

  it "ignores an unsupported tenant default and falls through to Accept-Language" do
    stub_customer_with("fr")
    request.headers["Accept-Language"] = "zh-CN,zh;q=0.9"
    get :index
    expect(response.body).to eq("zh-CN")
  end

  it "falls through to the default when the tenant has no configured locale" do
    stub_customer_with(nil)
    get :index
    expect(response.body).to eq("en")
  end

  it "falls back to the signed-in user's preference" do
    stub_user_with("zh-CN")
    get :index
    expect(response.body).to eq("zh-CN")
  end

  it "falls back to the cookie when no user preference is set" do
    stub_user_with(nil)
    request.cookies[:locale] = "zh-CN"
    get :index
    expect(response.body).to eq("zh-CN")
  end

  it "falls back to the Accept-Language header" do
    request.headers["Accept-Language"] = "zh-CN,zh;q=0.9,en;q=0.8"
    get :index
    expect(response.body).to eq("zh-CN")
  end

  it "ignores unsupported locales and falls through to the default" do
    get :index, params: { locale: "fr" }
    expect(response.body).to eq("en")
  end

  it "resets I18n.locale after the request" do
    get :index, params: { locale: "zh-CN" }
    expect(I18n.locale).to eq(:en)
  end
end
