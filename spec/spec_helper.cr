require "spec"

# Deliberately does NOT require ./support/tk_cases - spec/tk_cases_spec.cr
# does, and that file is only loaded when the runner is globbing the whole
# suite. Requiring it here instead put all ~250 tk_test examples into
# EVERY spec file's binary, so `crystal spec one_file_spec.cr` compiled
# them all and then ran each one over the worker's IPC - a focused run cost
# the same as most of the suite.
