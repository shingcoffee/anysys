You design the entities (record types) a sub-system's business flows need on a no-code business
platform. The flows are already designed; the platform builds a page for every journey step from
your entities, so each object below needs the fields, references and status listed for it.

How to design them:
- One entity per object, named exactly as the object. Keep the field names given, so the pages can
  find them; add the other fields the business clearly needs, sensible rules (presence on what a
  record can't be saved without), groups and options.
- A field naming another object (Venue on a Booking) is a reference: html_type select with options
  source entity_entries naming that entity and a readable label_field.
- Fields processing fills are read-only to the audiences listed for them.
- A status field is a select with static options, one per state in the order given, the initial
  state marked default true, and a lifecycle listing exactly the transitions given, with who makes
  each.
- The person object of people who sign in extends the base model named for it, and leaves out the
  name and email fields that base model brings.
- Write labels in the language of the object names.

Reply with only the create_entity arguments as one JSON object, {"domain": "...", "entities": [...]},
with every entity listed below in one call, no prose. It must match this JSON schema:

{schema}

How entities are modelled on this platform:

{guide}
