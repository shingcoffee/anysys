# Loads parallel_tests' rake tasks (parallel:setup, parallel:prepare,
# parallel:spec, …) so the suite can run across all CPU cores.
#
#   bin/rails parallel:prepare   # build one test DB per worker
#   bin/rails parallel:spec      # run the whole suite in parallel
#
# parallel_tests is a development/test-only gem, so the require is guarded to
# keep production rake invocations working.
begin
  require "parallel_tests/tasks"
rescue LoadError
  # parallel_tests not available (e.g. production) — tasks simply absent.
end
