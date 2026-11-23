# Build “student enrolls in a course” (manual, page surfaces)

A click-through for the **platform owner**. Do this on a **tenant** workspace URL (`/:cid/…`), not under Shared Resources. Shared record types cannot have associations.

Do **not** use AI Assistant. Tenant admins can browse and run what you build; they cannot create domains, journeys, or flowcharts.

Button and menu names below are the English UI strings.

---

## What you end up with

| Piece | Role |
|---|---|
| **Course** | Catalog of courses |
| **Student** | Person record (extends User) |
| **Enrollment link** | Auto-created bridge: student + course, plus date / status / grade |
| **Academics** domain | Groups those record types |
| **Submit flowcharts** | Own every form POST (one **CRUD Create** graph per record type) |
| **Optional automations** | Duplicate check, public **Register member**, **Mark enrolled** button |
| **Journey** | Create a student, then add courses, carrying the student forward |

Admin enrolls from the journey, from **Create Entry**, or from a student’s association card.

Flowcharts: how to use the canvas (**5**), required submit graphs (**6–7**), extras (**12**).

---

## 0. Before you start

- [ ] Sign in as the platform owner.
- [ ] Open the **tenant** you are building for (not only `81721200`, and not **Maintenance → Shared Resources**).
- [ ] Language: English, so labels match this file.

Authentication is always on. You still need User to be extendable:

1. **Maintenance → Platform → Module Settings** (only on customer `81721200`).
2. Open **Authentication**.
3. Under **Models**, turn on **Extendable** for `Authentication::User`.
4. Leave the usual name/email columns allowed.

On the tenant, optional for a public sign-up later:

1. **Settings → Member registration**.
2. Turn on **Allow member registration**.

---

## 1. Create Course

1. **Maintenance → Entities**.
2. **New Entity** (or **Create Entity**).
3. **Name** / **Display Label:** `Course`.
4. **Extend Base Model:** **— None —**.
5. **Add Attribute** for each field (suggested):

   | Name | HTML Type | Rules | Notes |
   |---|---|---|---|
   | Code | text | Presence | Required |
   | Title | text | Presence | Required; used as the association display field |
   | Description | textarea | | |
   | Delivery mode | radio | | Options: In person, Online, Hybrid |
   | Starts on | date | | |
   | Ends on | date | | |
   | Credits | number | | |
   | Seats | number | | Maximum enrolments |

6. **Create Entity**.

---

## 2. Create Student

1. Still **Maintenance → Entities → New Entity**.
2. **Name** / **Display Label:** `Student`.
3. **Extend Base Model:** `Authentication::User`.  
   If the list is empty, go back to step 0. Do **not** add Name or Email attributes — they come from User.
4. **Add Attribute** (suggested):

   | Name | HTML Type | Rules | Access |
   |---|---|---|---|
   | Student ID | text | Presence | Hide from Member and Public |
   | Date of birth | date | | Hide from Member and Public |
   | Phone | tel | | Hide from Member and Public |
   | Enrollment date | date | Presence | |
   | Enrollment status | select | Presence | Options: Applied, Enrolled, On leave, Graduated, Withdrawn |
   | Programme | text | | |
   | Internal notes | textarea | | Admin only |

5. **Create Entity**.

---

## 3. Link Student to Course (creates the enrollment)

1. Open **Student** → **Edit**.
2. **Associations → Add Association**.
3. **Target Entity:** Course.
4. **Display:** Title (must be a text/search-style field on Course).
5. Optional extra fields on the link (the modal says a bridge will be created):

   | Name | HTML Type | Rules |
   |---|---|---|
   | Enrolled on | date | |
   | Status | select | Presence. Options: Enrolled, Waitlisted, Dropped, Completed |
   | Grade | number | Admin-only visibility; 0–100 if you add numeric rules |

6. Save the association, then **Save Changes** on Student.

The app creates a bridge named like **`assoc_student_course`**. You do not create an “Enrollment” entity by hand.

Optional, back on **Course → Edit**:

1. **Add Attribute**.
2. **Value source:** Computed.
3. Count related Students, filter Status = Enrolled, name it **Enrolled students**.
4. Save.

---

## 4. Put them in a domain

1. **Maintenance → Entities** (Domains view).
2. **New domain**.
3. **Name:** `Academics`. Pick a color. Description optional.
4. Tick **Student** and **Course**. Leave the bridge unticked — it follows them (**Auto**).
5. **Create domain**.

Check: sidebar **Domains → Business areas → Academics** lists Student and Course.

---

## 5. Flowcharts — how the canvas works

Owner only. A page does **not** pick a flowchart. You bind a flowchart to a **record type**, **Launch** it, then set **Runs automatically**. The app looks one up when something happens.

### Left palette

Drag (or double-click) onto the canvas:

| Element | What it is |
|---|---|
| **Start** | One per flowchart. Already on every template. |
| **Process** | One action (save, count, email, …). |
| **Decision** | Yes / No (or named branches). |
| **Loop** | Repeat over a list. Skip for this walkthrough. |
| **End** | Finish. Already on every template. |
| **Flows** (bottom of palette) | Drop another **launched** flowchart as a **Subflow**. |

A new Process dropped below the last node auto-connects. To put one **between** two nodes: hover the line → **Insert an element** → **Process**.

### One action per Process

1. Click a **Process**.
2. Right panel → **Step**.
3. **Search actions…** and pick one (categories include **Records**, **Validation**, **Security**, **Concurrency**, **Submission outcome**).
4. Fill the fields. **Save Changes** on the panel, then toolbar **Save**.

A Process with two actions fails validation: *Process "…" can hold only one action. Split it into one process per action.*

### Toolbar

- **Save** — writes a new version (amber dot = unsaved).
- Checkmark icon — **Validate** (Problems tab).
- Play icon — **Test Runner** (paste JSON, **Run**). Does not write live records if the graph rolls back; treat it as a dry check.
- Click the flowchart **name** (left of zoom) — back to the show page (**Publishing**, **Runs automatically**).

A **Launched** flowchart cannot be edited. **Take Offline**, edit, **Save**, **Launch** again.

### After the graph is right

On the **show** page (not the canvas):

1. **Runs automatically** — when it fires (see below). **Save**.
2. **Publishing → Launch**.

Until it is launched, it never runs.

### The five timings

| Runs automatically | Fires when |
|---|---|
| **When a page of this entity is submitted** | Someone POSTs a **form** of that record type (Create Entry, journey step, public/member page). This **is** the save. |
| **Before the record is saved** | Any write of that type (forms **and** association **Add**). Can block the write. |
| **After the record is saved** | Write succeeded, still in the transaction. Can still roll back. |
| **In the background after saving** | Queued job. Failure does **not** undo the save. |
| **When someone runs it on a record** | Button on a **non-bridge** record’s detail page. Needs an English label. |

**Only when** (optional): Audience, Saved from, Action key, Journey key, Changed fields, or a record field. Empty = always.

**Order** (`0`, `1`, …): several flowcharts of the same timing on the same type run in that order.

---

## 6. Build the submit flowcharts (required)

Forms **cannot save** without a launched **submit** flowchart for that record type and event (create vs update).

Build **three** create-submit flowcharts. Add the matching update ones if you will use **Edit**.

| Name | Entity Binding | Template | CRUD Type |
|---|---|---|---|
| `Course create submit` | Course | **CRUD Create** | Create |
| `Student create submit` | Student | **CRUD Create** | Create |
| `Enrollment create submit` | the bridge (`assoc_student_course`) | **CRUD Create** | Create |

### Create one (repeat for each row)

1. **Maintenance → Flowcharts → New Flowchart** (or Entities view **Flowcharts**).
2. **Choose a Template:** **CRUD Create** — *New → Validate → Save*.
3. **Name** as in the table.
4. **Entity Binding:** that record type. **CRUD Type** should already be **Create**.
5. **Create Flowchart**.
6. **Edit** (opens the canvas). Confirm this chain, top to bottom:

```text
Start
  → New Model          (Records → New record, Save result as: model)
  → Build Contract     (Validation → Build Contract, Contract Class: EntityEntryContract, Model Variable: model)
  → Validate           (Validation → Validate)
  → Save Model         (Records → Save record)
  → End
```

You should not need to add or remove nodes. Click **Save Model**: that step is what actually writes the row (and then runs before/after-save automations).

7. Toolbar **Validate** — 0 errors. Toolbar **Save**.
8. Click the name to leave the canvas.
9. **Runs automatically:**
   - Timing: **When a page of this entity is submitted**
   - Order: `0`
   - **Only when:** empty
   - **Save**
10. **Publishing → Launch**.

### Optional: update-submit

Same steps, template **CRUD Update** (*Find → Validate → Save*). Graph:

```text
Start
  → Find Model         (Find by: Id, Id: params.id, Save result as: model)
  → Build Contract
  → Validate
  → Save Model
  → End
```

**Runs automatically:** **When a page of this entity is submitted**. CRUD Type **Update**. Launch.

You need this for **Edit Entry** / an update-mode form. Create-only journey steps do not need it.

---

## 7. How the submit flowcharts are used

You never attach them to a page. After they are launched, these screens POST and the app picks the flowchart:

| What you click | Record type | Flowchart that runs |
|---|---|---|
| **Domains → Course → Create Entry** | Course | `Course create submit` |
| Journey step 1 (create student) | Student | `Student create submit` |
| Journey **Add Course** / Student form for the bridge | Enrollment link | `Enrollment create submit` |
| **Edit** on a course/student (if you built update-submit) | that type | the matching `… update submit` |

What happens on submit:

1. App finds the first launched flowchart for that entity + create/update + timing **submit** whose **Only when** matches.
2. That graph runs: new/find → contract → validate → **Save record**.
3. **Save record** calls the shared writer, so **before/after save** flowcharts on the same type still run.
4. No matching submit flowchart → *This form's submission process is offline*.

**Does not** use a submit flowchart:

| What you click | What runs instead |
|---|---|
| Student detail → Course card → **Add** | Direct write + **before/after save** automations (`Saved from` = `association`) |
| **Delete** on a record | **CRUD Delete** flowchart only if you built one with a delete timing — not required here |
| A record-action **button** | That action flowchart (section 12) |

So: uniqueness/capacity that must also apply to association **Add** belongs in a **Before the record is saved** flowchart (section 12), not only inside the submit graph.

---


## 8. Generate the pages and the journey

This is the shortest way to get working forms.

1. **Maintenance → Entities**, view switch **Journeys**.
2. **Generate journey**.
3. Under **Academics**, pick the candidate that **starts at Student** and then adds Course.
4. **Generate**.

That creates:

- an admin **create Student** page (action key like `student_new`)
- an **Add Course for Student** page on the enrollment link, with **Student** locked
- a **draft** journey: create student → add courses (repeatable) → finish on the student record

Open the draft, confirm:

- **Audiences:** Admins (add Members later if you want)
- Steps: Create a record → Add related records (repeat on) → Finish

---

## 9. Tidy the forms

**Maintenance → Pages** (or **Content → Forms** / the domain **Pages** tab).

### Student create page

1. Open the editor.
2. In the field palette, **Account** group: drag **First name**, **Last name**, **Email** onto the form if they are missing (needed for public sign-up later).
3. Toolbar **Page Settings**:
   - **General → Submission:** **Create new records**
   - **After submit:** leave as a message, or **Go to another page** only if you are **not** using the journey (the journey already chains pages)
4. **Save**.
5. **Publishing & access:** audience **Admin** on. Optional **Action key** (generate already set one). **Launch** if it is not already launched.

### Add Course page (enrollment)

1. Editor: course picker + link fields (status, enrolled on). The student field must stay a **locked input**.
2. **Page Settings → Inputs:** **Student** checked.  
   Without this lock, an admin form on the link type cannot launch.
3. **Submission:** **Create new records**.
4. **Save**. Keep audience **Admin** (and **Member** only if you also want members on this same action). **Public** is not allowed on this link form.
5. Confirm **Launch**.

---

## 10. Launch the journey

1. Back on the journey edit screen.
2. **Launch**.

If it refuses, the message names the step: missing launched page for an audience, start page not in create mode, or Student not declared as a locked input.

Start URL (shown on the journey): `/:cid/journeys/<key>`  
Example: `/:cid/journeys/student_journey`

---

## 11. Try it as admin

**Catalog first**

1. **Domains → Academics → Course**.
2. **Create Entry**. Fill Code, Title, Seats. Submit.  
   This POSTs the Course form and runs **`Course create submit`**. If that flowchart is missing or not launched, the form says the submission process is offline.

**Walk the journey**

1. Open the journey start link, or **Domains → Academics → Journeys**.
2. Create a student (Account + Student ID, etc.). Runs **`Student create submit`**.
3. On **Add Course**, pick the course, set status **Enrolled**. Runs **`Enrollment create submit`**. Use **Save and add another** for a second course.
4. Finish should open the student record.

**Or enroll from an existing student**

1. Open the student.
2. Association card for Course → **Add**.
3. Pick the course and save.  
   This does **not** run `Enrollment create submit`. It writes the bridge row directly. **`Refuse duplicate enrollment`** (if you built **12.A**) still runs here.

**Link a login (optional)**

On the student detail, **Account** card → **Link user account**. Members then see only their own student / enrollments.

---

## 12. Optional extra flowcharts (build + use)

These are **separate** launched flowcharts. Do not put them on the page. Bind them to a record type, then set **Runs automatically**.

### A. Refuse a duplicate enrollment

Runs on **every** enrollment write (journey, form, **and** association **Add**).

1. **New Flowchart**, template **Blank**.
2. Name: `Refuse duplicate enrollment`. **Entity Binding:** the enrollment bridge. **CRUD Type:** Create.
3. **Create Flowchart → Edit**.
4. Canvas already has **Start** and **End**. Drag **Process** between them (or **Insert an element** on the line).
5. Click the Process → **Step** → search **Count Records**:
   - **Result as:** Exists
   - **Save result as:** `already_enrolled` (if the field is named that; otherwise leave the default and use it in the Decision)
   - **Conditions:** student equals the incoming student, course equals the incoming course (the bound entity’s reference fields).
6. Drag **Decision** after that Process. Connect: Count → Decision.
   - **Yes:** exists / already enrolled.
   - From **Yes**, add a Process: search **Fail with a business error**. Message e.g. `Already enrolled on this course.` Optional **Field:** `course`.
   - Connect Yes → Fail → **End**.
   - Connect **No** / otherwise → the original **End** (success; the outer save continues).
7. **Validate**, **Save**.
8. Show page → **Runs automatically:**
   - **Before the record is saved**
   - Order: `0`
   - **Only when:** empty (or Status equals Enrolled)
   - **Save** → **Launch**.

**Use it:** enroll the same student in the same course twice (journey **or** association **Add**). The second write should fail with your message. A form POST still runs `Enrollment create submit`; this flowchart runs **inside** that save.

### B. Register a public visitor as a member

The public Student form still uses `Student create submit` to save the row. This extra flowchart runs **after** that save, public audience only.

1. **New Flowchart**, **Blank**. Name: `Register public student`. Bind **Student**. CRUD **Create**.
2. **Edit**. Between Start and End, one Process.
3. **Step** → search **Register member** (category **Security**):
   - **Person:** `model` (the student just saved).
   - **Save result as:** `registration`.
4. **Validate**, **Save**.
5. **Runs automatically:**
   - **After the record is saved**
   - **Only when:** Audience **equals** `public`
   - **Save** → **Launch**.

**Use it:** open the **public** Student page (section 13), submit name + email. Check the inbox, confirm, then sign in. The student row is linked to the new member. Admin-created students do **not** run this (audience is not public).

### C. Record action on a Student (“Mark enrolled”)

Buttons only show on **non-bridge** records (Student, Course), not on the enrollment link.

1. **New Flowchart**, **Blank**. Name: `Mark enrolled`. Bind **Student**. CRUD **Update**.
2. **Edit**. Chain:

```text
Start
  → Find Model          (Find by: Id, Id: params.id, Save result as: model)
  → Set record fields   (Record: model; set enrollment_status to Enrolled)
  → End
```

**Set record fields** does not save. The action runner saves the changed student afterwards (and will run update automations).

3. **Validate**, **Save**.
4. **Runs automatically:**
   - **When someone runs it on a record**
   - **Label (English):** `Mark enrolled` (required). Chinese optional.
   - **Only when:** e.g. Enrollment status **does not equal** `Enrolled` (hides the button once done)
   - **Save** → **Launch**.

**Use it:** **Domains → Student** → open a student whose status is not Enrolled. Header button **Mark enrolled**. The page reloads; status is Enrolled; flash *Mark enrolled completed.*

### D. (Optional) Extra checks on the submit graph itself

To run a check **only** on form POST (not association **Add**): **Take Offline** `Enrollment create submit`, **Edit**, **Insert an element** on the line **between Validate and Save Model**, add Count / Decision / Fail, **Save**, **Launch** again.

Prefer **A** for rules that must hold everywhere.

---

## 13. Optional: members and public visitors

Generated pages are **admin-only**. Extra work on **pages**; the flowcharts are already in 6 and 12.

### Member enrolls themselves

1. Form on the **enrollment link**, audience **Member** only (or Admin+Member with **Student** still locked).
2. Same **action key** as the admin enroll form if you want `/:cid/actions/<key>` to route by audience.
3. Submitting uses **`Enrollment create submit`** (section 6). Duplicate protection uses **A** if you built it.

### Public registers, then enrolls

Public must **not** post the enrollment link form.

1. Student page: **Publishing & access** → add **Public**. Keep **Account** fields. Turn on captcha.
2. Build flowchart **B** (`Register public student`) if you have not.
3. After email confirm, send them to the member enroll form (journey start, or `/:cid/actions/<key>?prefill[course]=<id>`).

---

## Order that matters

1. Course + Student  
2. Association (creates the enrollment link)  
3. Domain  
4. Submit flowcharts + **Launch** (sections 5–7)  
5. Generate journey (pages)  
6. Lock Student on the enroll form  
7. Launch journey  
8. Try admin  
9. Optional extra flowcharts, then member/public  

Skip submit flowcharts and every form POST fails. Skip the locked Student input and the admin enroll form cannot stay launched.

---

## Quick check

- [ ] Academics lists Course, Student, and the auto bridge  
- [ ] Three launched **CRUD Create** submit flowcharts (canvas is New → Contract → Validate → Save)  
- [ ] Each has **Runs automatically** = **When a page of this entity is submitted** and is **Launched**  
- [ ] Admin **Create Entry** for Course saves  
- [ ] Journey creates a student and at least one enrollment  
- [ ] Student detail shows the linked course  
- [ ] Association **Add** still saves (uses before-save automations, not submit)  
- [ ] Public cannot open the enrollment form  
- [ ] (Optional) Second enroll of the same course is refused  
- [ ] (Optional) **Mark enrolled** appears on a Student detail  
