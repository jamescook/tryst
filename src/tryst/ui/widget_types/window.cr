require "../widget_type"
require "../../platform"

module Tryst
  module UI
    # A freshly created :window's post-creation setup: title/geometry/
    # resizable, transient-to-parent, the macOS shared-menubar quirk, and
    # withdrawn by default - a declared window stays hidden until
    # Handle#show reveals it, so a build can declare every window it will
    # ever need up front without them all flashing onto the screen at
    # realize.
    class WindowType < WidgetType
      def post_create(app : AppContract, node : Node, path : String, parent_path : String) : Nil
        opts = node.opts
        window = app.window(path)

        window.title = opts[:title].to_s if opts[:title]?
        window.geometry = opts[:geometry].to_s if opts[:geometry]?

        if opts.has_key?(:resizable)
          width, height = WindowType.resizable_pair(opts[:resizable])
          window.set_resizable(width, height)
        end

        if min_size = opts[:min_size]?
          width, height = WindowType.size_pair(min_size, "min_size")
          window.set_minsize(width, height)
        end

        if max_size = opts[:max_size]?
          width, height = WindowType.size_pair(max_size, "max_size")
          window.set_maxsize(width, height)
        end

        WindowType.share_macos_menu(app, path, parent_path) if Tryst.platform.darwin?

        # Transient is applied by Handle#show, not here. On Aqua a
        # transient window is mapped whenever its master is, so setting
        # it on a window that starts withdrawn makes that window appear
        # the moment the root does - which would defeat the point of
        # declaring windows up front and revealing them individually.
        window.withdraw
      end

      # resizable: true/false for both axes, or resizable: [width, height]
      # to set them separately. A plain class method, not an instance
      # one, like #share_macos_menu below - neither touches any per-type
      # state, and keeping them callable without a WidgetType instance is
      # what lets window_spec.cr exercise #share_macos_menu directly (see
      # its own comment on why that matters).
      def self.resizable_pair(value : TclArgValue) : Tuple(Bool, Bool)
        if value.is_a?(Array)
          unless value.size == 2
            raise ArgumentError.new("resizable: as a list needs exactly [width, height] " \
                                    "(got #{value.size} element(s): #{value.inspect})")
          end
          return {resizable_axis(value[0]), resizable_axis(value[1])}
        end

        both = resizable_axis(value)
        {both, both}
      end

      # One axis of resizable:. Bool is the expected spelling, Int32 the
      # other form Tk itself uses. Anything else is a mistake in the
      # build rather than a value to guess at.
      def self.resizable_axis(value : TclArgValue) : Bool
        case value
        when Bool  then value
        when Int32 then !value.zero?
        else
          raise ArgumentError.new("resizable: expects true/false or 1/0 (got #{value.inspect})")
        end
      end

      # min_size:/max_size: as a {width, height} Tuple (arrives here as a
      # 2-element Array via WidgetDSL#to_opts_hash's Tuple->Array
      # conversion). option_name names which option a bad value belongs
      # to, so the error points at the actual mistake.
      def self.size_pair(value : TclArgValue, option_name : String) : Tuple(Int32, Int32)
        unless value.is_a?(Array) && value.size == 2 && value.all?(Int32)
          raise ArgumentError.new("#{option_name}: expects {width, height} (got #{value.inspect})")
        end

        {value[0].as(Int32), value[1].as(Int32)}
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

    # A toplevel: placed by the window manager, never pack/gridded into
    # its nominal parent - hence arranged: false.
    WidgetTypes.register(
      WindowType.new(type: :window, tk_command: "toplevel", leaf: false, arranged: false, hosts_menu_bar: true)
    )
  end
end
