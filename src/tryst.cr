# Crystal bindings for Tcl/Tk. See src/tryst/interp.cr for the low-level
# bridge (mirrors ruby-tryst's compiled C extension layer); higher-level
# pieces (App, Widget, etc.) live in their own src/tryst/*.cr files as they
# land, one file per class - mirroring ruby-tryst's lib/tryst/*.rb layout.
require "./tryst/native_window"
require "./tryst/event_source"
require "./tryst/notifier"
require "./tryst/interp"
require "./tryst/values"
require "./tryst/platform"
require "./tryst/callback_registry"
require "./tryst/app"
require "./tryst/photo"
require "./tryst/theme"
require "./tryst/tween"
require "./tryst/owner_drawn_widget"
require "./tryst/background_work"
require "./tryst/menu_interceptor"
require "./tryst/tag_bind_interceptor"
require "./tryst/canvas_bind_interceptor"
