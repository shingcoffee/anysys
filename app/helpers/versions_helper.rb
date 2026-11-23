# frozen_string_literal: true

module VersionsHelper
  # Translated copy for the `versions` Stimulus controller
  # (app/javascript/controllers/versions_controller.js), delivered as
  # data-*-value attributes on the controller element.
  #
  # This MUST be merged into a `tag.div(data:)` hash — never rendered as a
  # partial spliced inside an opening tag. In development
  # `annotate_rendered_view_with_filenames` wraps a rendered partial in
  # `<!-- BEGIN ... -->` / `<!-- END ... -->` comments; injected inside a tag,
  # the comment's `-->` closes the tag early and the attributes spill into the
  # page as raw text.
  def versions_i18n_data
    data = {
      "versions-item-fallback-label-value": t("chrome.versions_modal.item_fallback"),
      "versions-count-singular-format-value": t("chrome.versions_modal.count_singular"),
      "versions-count-plural-format-value": t("chrome.versions_modal.count_plural"),
      "versions-cannot-set-default-msg-value": t("chrome.versions_modal.cannot_set_default"),
      "versions-shared-owner-only-msg-value": t("chrome.versions_modal.shared_owner_only"),
      "versions-set-default-failed-format-value": t("chrome.versions_modal.set_default_failed"),
      "versions-delete-confirm-format-value": t("chrome.versions_modal.delete_confirm"),
      "versions-cannot-delete-msg-value": t("chrome.versions_modal.cannot_delete"),
      "versions-delete-failed-format-value": t("chrome.versions_modal.delete_failed"),
      "versions-load-versions-failed-format-value": t("chrome.versions_modal.load_failed"),
      "versions-load-version-failed-format-value": t("chrome.versions_modal.load_version_failed"),
      "versions-network-error-format-value": t("chrome.versions_modal.network_error"),
      "versions-empty-title-label-value": t("chrome.versions_modal.empty_title"),
      "versions-empty-hint-label-value": t("chrome.versions_modal.empty_hint"),
      "versions-default-badge-label-value": t("chrome.versions_modal.default_badge"),
      "versions-latest-badge-label-value": t("chrome.versions_modal.latest_badge"),
      "versions-no-description-label-value": t("chrome.versions_modal.no_description"),
      "versions-set-default-button-label-value": t("chrome.versions_modal.set_default"),
      "versions-delete-button-label-value": t("common.actions.delete"),
      "versions-open-button-label-value": t("chrome.versions_modal.open"),
      "versions-create-page-button-label-value": t("chrome.versions_modal.create_page"),
      "versions-create-page-failed-format-value": t("chrome.versions_modal.create_page_failed"),
      "versions-pagination-range-format-value": t("chrome.versions_modal.pagination_range"),
      "versions-back-button-label-value": t("common.actions.back"),
      "versions-added-count-format-value": t("chrome.versions_modal.added_count"),
      "versions-removed-count-format-value": t("chrome.versions_modal.removed_count"),
      "versions-select-two-hint-label-value": t("chrome.versions_modal.select_two"),
      "versions-one-selected-hint-label-value": t("chrome.versions_modal.one_selected"),
      "versions-two-selected-hint-label-value": t("chrome.versions_modal.two_selected"),
      "versions-ready-to-compare-label-value": t("chrome.versions_modal.ready_to_compare"),
      "versions-pick-more-format-value": t("chrome.versions_modal.pick_more")
    }
    data["versions-path-prefix-value"] = "admin/maintenance/platform" if shared_resources_mode?
    data
  end
end
