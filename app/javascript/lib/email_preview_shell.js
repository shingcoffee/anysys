// Shared document shell for author-facing email iframe srcdoc.
// Keep CSS in sync with Emails::CompileTemplate.wrap_for_browser.
export function wrapEmailPreviewHtml(html) {
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 16px; line-height: 1.5; }
    img { max-width: 100%; height: auto; }
  </style>
</head>
<body>${html || ""}</body>
</html>`
}
