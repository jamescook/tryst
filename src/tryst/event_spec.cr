module Tryst
  # What App#bind/#unbind and Widget#bind/#unbind accept for an event -
  # never a raw Tk event-sequence string to spell by hand. See
  # EventSpec.resolve for what each shape means.
  alias EventArg = String | Symbol | Array(Symbol)

  # What App#bind/#unbind and Widget#bind/#unbind accept for subs: - a
  # single Symbol (BIND_SUBS) or raw %-code String, or an Array mixing
  # either, or nil for none.
  alias SubsArg = (Symbol | String | Array(Symbol | String))?

  # Resolves an EventArg into the real Tk event-sequence string #bind
  # sends to Tcl - the piece that lets a caller write :drop_file or
  # [:control, :s] instead of "<<DropFile>>" or "<Control-s>", without
  # ever having to know that double angle brackets mean "virtual" and a
  # single pair means "native".
  #
  # A bare Symbol is looked up against Tk's own real vocabulary (see the
  # tables below, sourced from bind(n) and Tk's own tk.tcl - not
  # guessed): found in EVENT_TYPES/KEYSYMS/CLICKS -> native, wrapped in
  # a single "<...>". Not found -> assumed virtual, snake_case
  # auto-camelized into PascalCase and wrapped in "<<...>>" - which
  # already produces the exact right string for most of Tk's own
  # built-in virtual events (:copy -> "<<Copy>>", :select_all ->
  # "<<SelectAll>>") with no table needed; VIRTUAL_ALIASES exists only
  # for the rare case where Tk's own chosen name doesn't match what
  # auto-camelizing would produce (:right_click -> "<<ContextMenu>>" -
  # see this bead's own investigation notes on why that specific one
  # needed a real cross-version probe rather than a guess).
  #
  # An Array is always a native modifier combo, joined with "-":
  # [:control, :s] -> "<Control-s>". Every element but the last must be
  # a MODIFIERS key; the last resolves through the same native lookup a
  # bare Symbol uses (so :click works standalone AND as a combo's last
  # element), falling back to its own to_s for a keysym not worth a
  # table entry (single letters/digits are already their own keysym).
  #
  # A String is the escape hatch, unchanged from #bind's original
  # behavior: passed through as-is if it already starts with "<",
  # otherwise wrapped in one "<...>" pair.
  module EventSpec
    # bind(n)'s own EVENT TYPES table, snake_case -> Tk's exact spelling.
    EVENT_TYPES = {
      :activate => "Activate", :deactivate => "Deactivate",
      :button => "Button", :button_press => "ButtonPress", :button_release => "ButtonRelease",
      :circulate => "Circulate", :circulate_request => "CirculateRequest",
      :colormap => "Colormap",
      :configure => "Configure", :configure_request => "ConfigureRequest",
      :create => "Create", :destroy => "Destroy",
      :enter => "Enter", :leave => "Leave",
      :expose => "Expose",
      :focus_in => "FocusIn", :focus_out => "FocusOut",
      :gravity => "Gravity",
      :key => "Key", :key_press => "KeyPress", :key_release => "KeyRelease",
      :map => "Map", :map_request => "MapRequest", :unmap => "Unmap",
      :motion => "Motion",
      :mouse_wheel => "MouseWheel", :touchpad_scroll => "TouchpadScroll",
      :property => "Property",
      :reparent => "Reparent",
      :resize_request => "ResizeRequest",
      :visibility => "Visibility",
    } of Symbol => String

    # Named/non-literal keysyms worth a friendly Symbol - printable ASCII
    # (a, 1, !) already IS its own keysym (bind(n)'s own wording) and
    # needs no entry. F1..F35 added below the literal below.
    KEYSYMS = {
      :return => "Return", :escape => "Escape", :tab => "Tab", :space => "space",
      :back_space => "BackSpace", :delete => "Delete", :linefeed => "Linefeed", :clear => "Clear",
      :home => "Home", :end => "End", :page_up => "Prior", :page_down => "Next",
      :up => "Up", :down => "Down", :left => "Left", :right => "Right",
      :insert => "Insert", :menu => "Menu", :print => "Print", :pause => "Pause",
      :scroll_lock => "Scroll_Lock", :sys_req => "Sys_Req",
      :caps_lock => "Caps_Lock", :num_lock => "Num_Lock",
      :shift_l => "Shift_L", :shift_r => "Shift_R",
      :control_l => "Control_L", :control_r => "Control_R",
      :alt_l => "Alt_L", :alt_r => "Alt_R",
      :meta_l => "Meta_L", :meta_r => "Meta_R",
      :super_l => "Super_L", :super_r => "Super_R",
      :kp_0 => "KP_0", :kp_1 => "KP_1", :kp_2 => "KP_2", :kp_3 => "KP_3", :kp_4 => "KP_4",
      :kp_5 => "KP_5", :kp_6 => "KP_6", :kp_7 => "KP_7", :kp_8 => "KP_8", :kp_9 => "KP_9",
      :kp_enter => "KP_Enter", :kp_add => "KP_Add", :kp_subtract => "KP_Subtract",
      :kp_multiply => "KP_Multiply", :kp_divide => "KP_Divide", :kp_decimal => "KP_Decimal",
      :kp_home => "KP_Home", :kp_end => "KP_End", :kp_up => "KP_Up", :kp_down => "KP_Down",
      :kp_left => "KP_Left", :kp_right => "KP_Right",
      :kp_insert => "KP_Insert", :kp_delete => "KP_Delete",
    } of Symbol => String
    (1..35).each { |num| KEYSYMS[:"f#{num}"] = "F#{num}" }

    # Mouse clicks - Button-1 (left/primary) is universal across every
    # platform and Tcl version checked (see this bead's investigation
    # notes); there is deliberately no :middle_click here - Button-2 is
    # "middle click" on X11/win32 but IS the context-menu button on
    # macOS Aqua specifically under Tcl/Tk 8.6 (not 9.x), a real
    # cross-version collision with no single correct static mapping. Use
    # the raw String escape hatch for that one.
    CLICKS = {
      :click => "Button-1", :double_click => "Double-Button-1", :triple_click => "Triple-Button-1",
      :release => "ButtonRelease-1",
      # X11 reports a wheel as Button-4/Button-5 presses rather than a
      # real MouseWheel event - unlike :middle_click, there's no
      # documented cross-platform collision for these two specifically,
      # so they're safe as plain detail aliases.
      :button4 => "Button-4", :button5 => "Button-5",
    } of Symbol => String

    # Modifier prefixes for an Array combo. Deliberately excludes the raw
    # Mod1-Mod5 forms bind(n) also allows - which physical key a ModN is
    # depends on the platform's own modifier map (bind(n): "Most of the
    # modifiers have the obvious X meanings" is explicitly NOT true of
    # Mod1-5), so exposing them here would just relocate the same
    # cross-platform hazard CLICKS' own comment describes. Control/Alt/
    # Shift/Lock/Extended/Command/Option/Meta are Tk's own fixed, portable
    # names; Double/Triple/Quadruple are click-count prefixes. ButtonN
    # (unlike ModN) has a fixed, portable meaning - "this button is
    # currently held" - used as a modifier for e.g. drag events
    # ([:button1, :motion] -> "<Button1-Motion>", "while button 1 is
    # held"), distinct from CLICKS' :click ("Button-1", the press event
    # itself).
    MODIFIERS = {
      :control => "Control", :shift => "Shift", :alt => "Alt", :lock => "Lock",
      :extended => "Extended", :command => "Command", :option => "Option", :meta => "Meta",
      :double => "Double", :triple => "Triple", :quadruple => "Quadruple",
      :button1 => "Button1", :button2 => "Button2", :button3 => "Button3",
      :button4 => "Button4", :button5 => "Button5",
    } of Symbol => String

    # Friendly synonyms whose auto-camelized spelling would NOT match the
    # Tk-native (or otherwise correct) name they're meant to reach. Every
    # OTHER Tk-provided virtual event (Copy, Cut, SelectAll, ContextMenu
    # itself, ...) already camelizes correctly from its own natural
    # snake_case spelling and needs no entry - this table only holds the
    # exceptions. :right_click -> "ContextMenu" specifically: verified
    # directly (not guessed) that Tk's own tk.tcl defines <<ContextMenu>>
    # as the portable right-click virtual event, correct across platform
    # AND across Tcl 8.6 vs 9.x despite them using different physical
    # button numbers underneath (Button-2 vs Button-3 on macOS) - see
    # this bead's own investigation notes for the probe that confirmed it.
    VIRTUAL_ALIASES = {
      :right_click => "ContextMenu",
    } of Symbol => String

    def self.resolve(event : String) : String
      event.starts_with?('<') ? event : "<#{event}>"
    end

    def self.resolve(event : Symbol) : String
      if detail = native_detail(event)
        "<#{detail}>"
      elsif tk_name = VIRTUAL_ALIASES[event]?
        "<<#{tk_name}>>"
      else
        "<<#{camelize(event)}>>"
      end
    end

    def self.resolve(event : Array(Symbol)) : String
      raise ArgumentError.new("an event combo needs at least one symbol") if event.empty?

      *modifiers, last = event
      parts = modifiers.map do |modifier|
        MODIFIERS[modifier]? || raise ArgumentError.new(
          "#{modifier.inspect} isn't a recognized modifier for an event combo - known: #{MODIFIERS.keys.join(", ")}")
      end
      parts << (native_detail(last) || last.to_s)
      "<#{parts.join('-')}>"
    end

    # A single alphanumeric character IS its own keysym (bind(n): "they
    # include all the alphanumeric ASCII characters" - unlike punctuation,
    # which gets a NAMED keysym instead, e.g. "comma" for ",", not in this
    # table and not covered by this pattern either), so :a needs no table
    # entry to resolve natively as "a" rather than falling through to
    # virtual as "<<A>>".
    LITERAL_KEYSYM = /\A[a-zA-Z0-9]\z/

    # nil means "not a recognized native name" - the caller decides what
    # that means (virtual, for a bare Symbol; a literal keysym/button
    # passed through as-is, for a combo's last element).
    private def self.native_detail(name : Symbol) : String?
      literal = name.to_s
      return literal if literal.matches?(LITERAL_KEYSYM)
      EVENT_TYPES[name]? || KEYSYMS[name]? || CLICKS[name]?
    end

    private def self.camelize(name : Symbol) : String
      name.to_s.split('_').map(&.capitalize).join
    end
  end
end
