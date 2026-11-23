Every form page runs one piece of form processing when it is submitted: it validates the entry, saves
it and runs any follow-up work. New pages use the shared "Save page record". Call
`set_page_processing` only when the admin asks for a page to use different processing the workspace
already has; `list_catalog` lists those under `processing`.

- Name the page by its action key and audience as `list_catalog` lists them. Never invent a key.
- Name the processing exactly as the admin did. When it is not found, the violation lists close
  names: ask the admin which one they meant instead of guessing.
- A launched page accepts only launched processing that fits the page's entity. When the change is
  refused, tell the admin why instead of trying other processing.
- Setting processing does not create or change it. New processing is written by a sub-system build
  (`start_subsystem_build`).

```json
{"tool": "set_page_processing", "arguments": {"page": "student_new", "audience": "admin", "processing": "Save student and notify registrar"}}
```
