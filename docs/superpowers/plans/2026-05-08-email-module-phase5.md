# Email Module Implementation Plan - Phase 5: Flowchart Integration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Add email sending capabilities as flowchart step actions, allowing users to send transactional emails from within flowchart workflows.

**Architecture:** New step action `SendEmail` that uses `Email::Gateway.send` with template key and variables from flowchart context.

**Tech Stack:** Trailblazer Activity for step logic, existing Email::Gateway API

---

## File Structure

```
app/services/step_actions/
├── send_email.rb              # Step action implementation

app/services/step_action_configs/
├── send_email.rb              # Action config for canvas UI

spec/services/step_actions/
├── send_email_spec.rb         # Tests
```

---

### Task 1: Create SendEmail Step Action

**Files:**
- Create: `app/services/step_actions/send_email.rb`
- Create: `spec/services/step_actions/send_email_spec.rb`

The step action should:
1. Read template_key from step config
2. Read recipient email from ctx (entity entry field or explicit)
3. Build vars hash from step config mappings
4. Call Email::Gateway.send
5. Store message ID in ctx for downstream steps

---

### Task 2: Create SendEmail Action Config

**Files:**
- Create: `app/services/step_action_configs/send_email.rb`

Defines the canvas UI config:
- template_key: dropdown of customer's email templates
- to_field: text field or entity field selector
- vars: key-value mapping UI

---

### Task 3: Register Action in Constants

**Files:**
- Modify: `app/javascript/flowchart/constants/action_configs/index.js` (or equivalent)

Add SendEmail to available step actions.

---

### Task 4: Test Integration

- Create a test flowchart with SendEmail step
- Execute and verify email is queued
- Check EmailMessage record created

---

### Task 5: Commit

```bash
git add app/services/step_actions/send_email.rb app/services/step_action_configs/send_email.rb spec/
git commit -m "feat(email): add SendEmail flowchart step action"
```

---

## Phase 5 Complete

Email sending integrated into flowchart system:
- SendEmail step action for transactional emails
- Template selection from customer's templates
- Variable mapping from flowchart context
- Full audit trail via EmailMessage records
