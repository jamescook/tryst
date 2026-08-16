# Crystal bindings for Tcl/Tk. See src/teek/interp.cr for the low-level
# bridge (mirrors ruby-teek's compiled C extension layer); higher-level
# pieces (App, Widget, etc.) live in their own src/teek/*.cr files as they
# land, one file per class - mirroring ruby-teek's lib/teek/*.rb layout.
require "./teek/native_window"
require "./teek/event_source"
require "./teek/notifier"
require "./teek/interp"
require "./teek/values"
require "./teek/platform"
require "./teek/callback_registry"
require "./teek/app"
require "./teek/photo"
require "./teek/background_work"
require "./teek/menu_interceptor"
require "./teek/tag_bind_interceptor"
require "./teek/canvas_bind_interceptor"
