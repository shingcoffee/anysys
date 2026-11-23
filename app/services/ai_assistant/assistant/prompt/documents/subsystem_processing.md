Build request from the sub-system build (the admin did not type this message):

Write one flowchart named "{name}". It processes every submission of the {audience} form page
"{page}", whose records are {entity}. It replaces the page's default processing, so it must first save
the submitted page record (build_contract → validate_contract → save_model) and then do this:

{purpose}

Values the admin gave for it:
{values}

Questions the build asked the admin, each followed by their reply:
{answers}
{current}
Rules:
- Save everything the journey's next page needs: the records it shows or edits are carried to it
  automatically, so the page loads them itself; never query records just to pass them on.
- A status field with a lifecycle changes only along its allowed transitions, for the person
  submitting; any other change is refused when the record is saved. To move it, use transition_state
  on the page record and leave its transitions empty: it then follows the record's lifecycle. Never
  set a status a payment confirms on submit: put it in request_payment's paidFields instead.
- Use only web addresses and email addresses that appear word for word in the admin's own messages.
  When one is missing, reply with intent "clarify", a one-line reply, and "questions": one
  {"prompt": "...", "type": "text"} per missing value, written in the admin's language. Never guess one.
- Never put a password, token or secret into a step. Leave that field empty, or leave the step out,
  and name what the admin still has to set up in "needs_setup": a list of short phrases in the
  admin's language.
- The admin reads your questions, "needs_setup" and reply. Describe what happens when the form is
  submitted in everyday words: never say "flowchart" and never name step or field keys.
- Otherwise reply with intent "apply_flowchart" and the whole flowchart.
