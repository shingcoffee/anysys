# NodeJS Removal Implementation Plan

> **For Copilot:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove all NodeJS artifacts from the Rails 8 application that already uses importmap-rails, propshaft, and tailwindcss-rails gem.

**Architecture:** No architectural changes - simply delete NodeJS files (package.json, package-lock.json, node_modules/, spec/javascript/) and verify the app still works.

**Tech Stack:** Rails 8, importmap-rails, propshaft, tailwindcss-rails gem, RSpec

---

### Task 1: Delete NodeJS Configuration Files

**Files:**
- Delete: `package.json`
- Delete: `package-lock.json`

**Step 1: Delete package.json**

```bash
rm /opt/ai_coding/anysys/package.json
```

**Step 2: Delete package-lock.json**

```bash
rm /opt/ai_coding/anysys/package-lock.json
```

**Step 3: Verify files are deleted**

Run: `ls -la /opt/ai_coding/anysys/package*.json 2>&1`
Expected: "No such file or directory" for both files

---

### Task 2: Delete node_modules Directory

**Files:**
- Delete: `node_modules/` (entire directory, 54MB)

**Step 1: Delete node_modules directory**

```bash
rm -rf /opt/ai_coding/anysys/node_modules
```

**Step 2: Verify directory is deleted**

Run: `ls -d /opt/ai_coding/anysys/node_modules 2>&1`
Expected: "No such file or directory"

---

### Task 3: Delete Jest Test Files

**Files:**
- Delete: `spec/javascript/lib/condition_evaluator_spec.js`
- Delete: `spec/javascript/lib/formula_engine_spec.js`
- Delete: `spec/javascript/` (entire directory if empty after)

**Step 1: Delete Jest test files**

```bash
rm -rf /opt/ai_coding/anysys/spec/javascript
```

**Step 2: Verify directory is deleted**

Run: `ls -d /opt/ai_coding/anysys/spec/javascript 2>&1`
Expected: "No such file or directory"

---

### Task 4: Verify RSpec Tests Still Pass

**Step 1: Run RSpec test suite**

Run: `cd /opt/ai_coding/anysys && bundle exec rspec --format progress`
Expected: All tests pass (no failures related to NodeJS removal)

**Step 2: Note any failures**

If any failures occur, they are unrelated to NodeJS removal (investigate separately).

---

### Task 5: Verify Rails Asset Pipeline Works

**Step 1: Verify Tailwind CSS compiles**

Run: `cd /opt/ai_coding/anysys && bin/rails tailwindcss:build`
Expected: Tailwind CSS compiles without errors

**Step 2: Verify importmap is valid**

Run: `cd /opt/ai_coding/anysys && bin/rails importmap:verify`
Expected: No errors (or command may not exist - that's fine)

**Step 3: Verify assets precompile**

Run: `cd /opt/ai_coding/anysys && bin/rails assets:precompile RAILS_ENV=production`
Expected: Assets compile successfully without NodeJS

**Step 4: Clean up precompiled assets**

Run: `cd /opt/ai_coding/anysys && bin/rails assets:clobber`
Expected: Precompiled assets removed

---

### Task 6: Update .gitignore (if needed)

**Files:**
- Check: `.gitignore`

**Step 1: Check if node_modules is in .gitignore**

Run: `grep -n "node_modules" /opt/ai_coding/anysys/.gitignore`
Expected: Line containing `node_modules` (if not present, add it)

**Step 2: Add node_modules to .gitignore if missing**

Only if Step 1 shows no results:
```bash
echo "node_modules/" >> /opt/ai_coding/anysys/.gitignore
```

---

### Task 7: Final Verification

**Step 1: Check no NodeJS artifacts remain**

Run: `ls /opt/ai_coding/anysys/package*.json /opt/ai_coding/anysys/node_modules 2>&1`
Expected: "No such file or directory" for all

**Step 2: Verify app starts**

Run: `cd /opt/ai_coding/anysys && bin/rails runner "puts 'Rails OK'"`
Expected: Output "Rails OK"

**Step 3: Summary**

NodeJS removal complete. The app now runs entirely on Rails 8 stack:
- CSS: tailwindcss-rails gem
- JS: importmap-rails + Stimulus
- Assets: Propshaft

---

## Completion Checklist

- [ ] `package.json` deleted
- [ ] `package-lock.json` deleted
- [ ] `node_modules/` deleted
- [ ] `spec/javascript/` deleted
- [ ] RSpec tests pass
- [ ] Tailwind CSS compiles
- [ ] Assets precompile
- [ ] `node_modules` in `.gitignore`
