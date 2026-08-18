# tk_test cases, split by domain under tk_cases/ - this file is now just
# the aggregator both requirers (spec/tk_cases_spec.cr and
# spec/support/tk_worker.cr) already pointed at, so neither needed to
# change: both just `require "./tk_cases"`/`"./support/tk_cases"`, and
# get every case below transitively, the same as when they all lived
# here directly. See tk_test_registry.cr's own doc comment for why the
# cases live in support/ at all (the worker binary requires them too),
# and .claude/rules/testing.md for the tk_test/persistent-worker design
# this whole file exists to serve.
require "./tk_cases/interp_core"
require "./tk_cases/command_dispatch"
require "./tk_cases/window"
require "./tk_cases/app_utilities"
require "./tk_cases/text_metrics"
require "./tk_cases/grab_modal"
require "./tk_cases/widget_core"
require "./tk_cases/bind_callbacks"
require "./tk_cases/menus"
require "./tk_cases/text_tag_binds"
require "./tk_cases/canvas_item_binds"
require "./tk_cases/variables"
require "./tk_cases/package_management"
require "./tk_cases/timers"
require "./tk_cases/clipboard_dialogs"
require "./tk_cases/concurrency"
require "./tk_cases/realizer"
require "./tk_cases/photo"
require "./tk_cases/canvas_widget"
require "./tk_cases/theme"
require "./tk_cases/ui_handle"
require "./tk_cases/text_content"
require "./tk_cases/widget_dsl"
require "./tk_cases/native_window_handle"
require "./tk_cases/event_sources"
