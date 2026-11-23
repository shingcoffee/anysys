# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ActiveStorage direct uploads", type: :request do
  it "does not mint a blob on the unauthenticated Rails upload endpoint" do
    expect {
      post "/rails/active_storage/direct_uploads", params: {
        blob: {
          filename: "x.png",
          byte_size: 4,
          checksum: "rL0Y20zC+Fzt72VPzMSk2A==",
          content_type: "image/png"
        }
      }
    }.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:not_found)
  end
end
