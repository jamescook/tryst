require "./spec_helper"

# Turns spec/support/tk_cases.cr's tk_test cases into real spec examples.
# Its own file rather than a require in spec_helper.cr, so only a run that
# globs the whole suite pays for them: they compile into whatever binary
# loads them and each one is an IPC round trip to the persistent worker
# (see .claude/rules/testing.md), which a focused run of one unrelated
# file has no reason to carry.
#
# Nothing else belongs here. The cases themselves stay in support/, where
# the worker binary also requires them - that dual role is the whole
# reason they aren't written as ordinary examples in the first place.
require "./support/tk_cases"
