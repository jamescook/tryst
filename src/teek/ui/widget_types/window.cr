require "../widget_type"
require "../../platform"

module Teek
  module UI
    # @api private
    #
    # A freshly created :window's post-creation setup: title/geometry/
    # resizable, transient-to-parent, the macOS shared-menubar quirk, and
    # withdrawn by default - a declared window stays hidden until
    # Handle#show reveals it, so a build can declare every window it will
    # ever need up front without them all flashing onto the screen at
    # realize. Registered as :window's own post_create: below.
    module WindowRealize
      def self.post_create(app : AppContract, node : Node, path : String, parent_path : String) : Nil
        opts = node.opts
        window = app.window(path)

        window.set_title(opts[:title].to_s) if opts[:title]?
        window.set_geometry(opts[:geometry].to_s) if opts[:geometry]?

        if opts.has_key?(:resizable)
          width, height = resizable_pair(opts[:resizable])
          window.set_resizable(width, height)
        end

        # Transient means the window manager treats this as a subordinate
        # of its parent - it stays above it, and usually skips the
        # taskbar. Opt out with transient: false for a genuinely
        # independent second window.
        app.command(:wm, :transient, path, parent_path) unless opts[:transient]? == false
        share_macos_menu(app, path, parent_path) if Teek.platform.darwin?

        window.withdraw
      end

      # resizable: true/false for both axes, or resizable: [width, height]
      # to set them separately.
      def self.resizable_pair(value : TclArgValue) : Tuple(Bool, Bool)
        return {truthy?(value[0]?), truthy?(value[1]?)} if value.is_a?(Array)

        both = truthy?(value)
        {both, both}
      end

      # Tk spells a boolean several ways, and an opts value arrives as
      # whatever the caller wrote - Bool is the expected one, Int32 the
      # other form Tk itself uses.
      def self.truthy?(value) : Bool
        case value
        when Bool  then value
        when Int32 then !value.zero?
        else            true
        end
      end

      # Every platform except macOS gives each window its own menu bar;
      # macOS has a single app-wide one, so a new window there falls back
      # to Tk's default "wish" menu unless it's pointed at the parent's.
      def self.share_macos_menu(app : AppContract, path : String, parent_path : String) : Nil
        # Purely cosmetic, and -menu only exists on a toplevel - a window
        # declared inside a frame has a parent with no such option, which
        # is a Tcl error rather than an empty string. Nothing to do in
        # that case, and it shouldn't take the window down with it.
        parent_menu = app.command(parent_path, :cget, "-menu")
        app.command(path, :configure, menu: parent_menu) unless parent_menu.empty?
      rescue TclError
        nil
      end
    end
  end
end

# A toplevel: placed by the window manager, never pack/gridded into its
# nominal parent - hence arranged: false.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :window, tk_command: "toplevel", leaf: false, arranged: false,
    post_create: ->Teek::UI::WindowRealize.post_create(Teek::UI::AppContract, Teek::UI::Node, String, String)
  )
)
