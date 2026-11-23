# Simplified Email Template Creation & Dry-Run Testing

## Introduction / Background
The current email template creation and edit workflow is spread across large, intimidating forms. Additionally, users must save a template before they can use the "Live Preview" or "Send Test" (dry-run) capabilities. 

This design simplifies the template creation page (`/:cid/admin/modules/emails/templates/new`) and the edit page, organizing them into a modern two-column layout. It also introduces interactive, real-time AJAX previewing and test-sending for both new (unpersisted) and existing (modified but unsaved) templates.

## User Experience (UX) Layout
Instead of a cramped side-by-side layout, we organize the template workspace into a spacious, full-width Tabbed Form Workspace using the Stimulus `tabs` controller. The user can switch between three focused tabs:

1. **✍️ Compose Content Tab (`data-tabs-id="content"`):**
   - **Core Details Card:** Houses the template Name and Subject fields spanning the full desktop width. Contains clear variable interpolation hints.
   - **Email Body Card:** Houses the Editor Switcher (Rich Text / Lexxy vs HTML Code), the corresponding active full-width editor (Action Text editor or HTML text area), and the full-width Plain Text Fallback textarea. 
   - No sidebar constraints allow the composer and editors to expand beautifully across the screen, ensuring a comfortable writing and coding experience.

2. **⚙️ Settings & Delivery Tab (`data-tabs-id="settings"`):**
   - **Settings Card:** Arranges configuration fields (Slug Key, Template Type, Category, Status, Message Stream, and custom variables definition) in a clean, modern, spacious two-column grid. This isolates technical setups from the primary writing canvas.

3. **👁️ Live Preview & Test-Send Tab (`data-tabs-id="preview"`):**
   - **Unified Live Preview Card:** A gorgeous mock email client interface that loads the rendered template dynamically via AJAX when the user clicks the tab (using standard multi-action triggers).
   - Displayed full-width, giving a highly accurate desktop rendering experience (not squashed).
   - Includes a **Simulated Envelope Header** containing the rendered Subject.
   - Includes a spacious body previewer with tabs to switch between the **🌐 HTML Body** (iframe) and the **📄 Plain Text** representation.
   - Includes an integrated **Dry-Run Test-Send Box** spanning horizontally to easily input a recipient address and trigger an actual email delivery with instant, inline feedback.

## Backend Changes

### 1. Routes (`config/routes.rb`)
Add `preview` and `test_send` POST routes under the templates collection namespace, alongside the existing member routes:
```ruby
resources :templates, only: %i[index new create edit update destroy] do
  member do
    post :test_send
    post :preview
  end
  collection do
    post :test_send
    post :preview
  end
end
```

### 2. TemplatesController (`app/controllers/admin/modules/emails/templates_controller.rb`)
- Modify `before_action :load_template` to skip if `params[:id]` is not present (i.e., when posting to collection endpoints):
  ```ruby
  before_action :load_template, only: %i[edit update destroy test_send preview], if: -> { params[:id].present? }
  ```
- In both `preview` and `test_send`, support instantiating/overriding template state:
  ```ruby
  if params[:email_template].present?
    @template ||= ::Emails::Template.new(customer: current_customer)
    @template.assign_attributes(template_params)
  end
  ```
- In `preview`, if `editor_type` is `"rich_text"`, manually compile the Action Text body:
  ```ruby
  if @template.editor_type == "rich_text"
    @template.body_html = @template.body.present? ? ::Emails::CompileTemplate.call(@template) : ""
  end
  ```
- In `test_send`, add support for JSON response format:
  ```ruby
  respond_to do |format|
    format.html do
      redirect_to(request.referer || "/#{current_customer.id}/admin/modules/emails/templates", notice: notice)
    end
    format.json do
      render json: { success: true, message: notice }
    end
  end
  ```
  And rescue error states or invalid emails to render a JSON error payload:
  ```ruby
  if invalid.any?
    respond_to do |format|
      format.html { redirect_to(...) and return }
      format.json { render json: { success: false, error: t("admin_modules.flash.templates.invalid_email", email: invalid.first) }, status: :unprocessable_entity and return }
    end
  end
  ```

## Frontend Changes

### 1. Layout View (`_form.html.erb`)
We will rewrite `app/views/admin/modules/emails/templates/_form.html.erb` to implement the responsive side-by-side grid, moving settings to the sidebar and adding the interactive Dry-Run panel.

### 2. Stimulus Controller (`remote_template_preview_controller.js`)
We will replace the current implementation of `app/javascript/controllers/remote_template_preview_controller.js` to make it incredibly powerful and fully interactive:
- **Form Data Gathering:** Scans the form for standard field inputs (Subject, Editor Type, textareas) and locates Action Text inputs (Trix/Lexxy hidden `name="email_template[body]"`) to build a complete `email_template` payload on the fly.
- **AJAX Preview:** Sends the payload to the configured `preview` URL (collection or member) and populates the subject pane, iframe `srcdoc`, and text panel with the rendered result.
- **AJAX Dry-Run Send:** Sends the payload plus the custom `to` recipient to the `test_send` URL. Disables inputs during sending, displays a loading spinner or "Sending..." text, and renders success/error messages on the screen using clean I18n strings.

## I18n Translations
Every button label, tab name, input placeholder, and flash message will be fully localized for both English (`en`) and Simplified Chinese (`zh-CN`). No user-facing hardcoded text will be used.

## Verification & Testing
- **Request Specs:** Comprehensive specs for the new collection endpoints `POST /preview` and `POST /test_send` verifying they successfully compile, render, and send transactional emails for unpersisted templates.
- **Frontend Specs:** Update or add JS unit tests using Vitest to maintain 100% line/branch coverage of modified Javascript controllers.
- **RSpec Run:** Ensure all email-related specs pass.
