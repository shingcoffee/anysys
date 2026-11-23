# Timing log — test suite speedup

All runs: `bin/rails parallel:spec`, 4 workers, serialized (nothing else touching the test DBs).

| Gate | Wall time | Examples | Failures | Notes |
|------|-----------|----------|----------|-------|
| Phase 0 baseline | 5:54 (354s) | 14,237 | 2 | Slowest tier finished in 4:46.9. Both failures were a pre-existing midnight-boundary flake in `charge_due_subscriptions_spec.rb` (order refs built with `Date.today`/`Time.zone.today` vs production's `next_charge_at.to_date`; only fails 00:00–01:00 UTC). Fixed in the spec before Phase 1; file green in isolation (23/23). |
| Gate 1 (after Phase 1) | 2:51 (171s) | 14,238 | 0 | `seed_admin_grants` batched via `insert_all!`; `create(:customer)` 163.1 → 42.3 ms/call. |
| Gate 1 confirm | 2:51 (171s) | 14,238 | 0 | Second consecutive green run at the same wall time. **Target met — Phase 2 (let_it_be sweep) and Phase 3 (AnyFixture) not built, per the measure-gated design.** |

## Conclusion

Gate 1 passed: 5:54 → 2:51 (−52%) from the single production-code change (batching admin grant seeding). The suite gained one example (+1: the new pin spec) and lost the two midnight-flake failures. No spec-fixture semantics were changed anywhere — the `let_it_be` sweep and shared-fixture contingency were never needed.
