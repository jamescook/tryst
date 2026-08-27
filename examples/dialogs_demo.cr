# Interactive example - run with `crystal run examples/dialogs_demo.cr`.
# Port of ruby-tryst's sample/dialogs/dialogs_demo.rb - exercises every
# safe Tk dialog wrapper (choose_open_file, choose_save_file,
# message_box, choose_color, popup_menu) so a human can click through
# each one and visually confirm it opens correctly and the wrapper
# reports back the right result.
#
# Not a "real" app - a manual test harness for App#choose_open_file/
# #choose_save_file/#message_box/#choose_color/#popup_menu, built
# specifically to exercise options containing spaces (try picking/typing
# a filename like "my file.png") and to show multi-pattern filetypes
# work.
require "../src/tryst"

class DialogsDemo
  getter app : Tryst::App

  # Assigned directly in #initialize (not via a helper method) - see the
  # comment above the button/menu wiring below for why.
  @log : Tryst::Widget
  @context_menu : Tryst::Widget

  def initialize
    @app = Tryst::App.new(title: "Dialog Wrappers Demo")
    @app.set_window_geometry("480x360")

    @app.create_widget("ttk::label",
      text: "Click each button below, then try options with spaces in them\n" \
            "(a filename, a title...) to confirm nothing gets mangled.\n" \
            "Right-click anywhere below the buttons for the popup menu.",
      justify: :left).pack(side: :top, fill: :x, padx: 8, pady: 8)

    buttons = @app.create_widget("ttk::frame")
    buttons.pack(side: :top, fill: :x, padx: 8, pady: 4)

    open_btn = plain_button(buttons, "Choose Open File...")
    save_btn = plain_button(buttons, "Choose Save File...")
    msgbox_btn = plain_button(buttons, "Message Box...")
    color_btn = plain_button(buttons, "Choose Color...")
    popup_btn = plain_button(buttons, "Popup Menu...")

    @log = @app.create_widget(:text, height: 10, wrap: :word, state: :disabled)
    @log.pack(side: :bottom, fill: :both, expand: 1, padx: 8, pady: 8)

    @context_menu = @app.menu(".dialogs_demo_ctx")

    # Button commands and menu entries are wired here, after @log and
    # @context_menu are already assigned above, rather than at
    # creation time - a real Crystal quirk, confirmed directly: a &block
    # parameter captured-and-stored as a Proc (App#callback's shape)
    # makes the compiler conservatively treat any instance-variable read
    # inside that block's call graph (here, every demo_* method calls
    # #log, which reads @log) as reachable at the point the block is
    # created, even though it's only ever actually invoked later from
    # Tcl. See examples/threading_demo_ui/app.cr's #wire_actions for the
    # same issue in more detail.
    open_btn.command(:configure, command: @app.callback { demo_choose_open_file })
    save_btn.command(:configure, command: @app.callback { demo_choose_save_file })
    msgbox_btn.command(:configure, command: @app.callback { demo_message_box })
    color_btn.command(:configure, command: @app.callback { demo_choose_color })
    popup_btn.command(:configure, command: @app.callback { demo_popup_menu })

    @context_menu.command(:add, :command, label: "Say Hello",
      command: @app.callback { log("popup_menu entry chosen -> Say Hello") })
    @context_menu.command(:add, :command, label: "Say Goodbye",
      command: @app.callback { log("popup_menu entry chosen -> Say Goodbye") })
    @context_menu.command(:add, :separator)
    @context_menu.command(:add, :command, label: "(just closes the menu)", command: @app.callback { })

    @log.bind(:right_click) { demo_popup_menu }
  end

  def run : Nil
    # Not #show plus a hand-rolled `wm attributes -topmost 1`: that pins
    # this window above every later one, so each dialog below would open
    # BEHIND it and refuse to be raised over it. #bring_to_front releases
    # the pin once the window is up.
    @app.bring_to_front
    @app.mainloop
  end

  private def plain_button(parent : Tryst::Widget, label : String) : Tryst::Widget
    btn = @app.create_widget("ttk::button", parent: parent, text: label)
    btn.pack(side: :top, fill: :x, padx: 4, pady: 2)
    btn
  end

  private def demo_choose_open_file : Nil
    result = @app.choose_open_file(
      title: "Choose a file to open (try one with spaces in the name)",
      filetypes: [{"Images", [".png", ".jpg", ".gif"]}, {"Text Files", ".txt"}, {"All Files", "*"}])
    log("choose_open_file -> #{result.inspect}")
  end

  private def demo_choose_save_file : Nil
    result = @app.choose_save_file(
      title: "Choose where to save",
      initialfile: "my file.txt",
      filetypes: [{"Text Files", ".txt"}, {"All Files", "*"}])
    log("choose_save_file -> #{result.inspect}")
  end

  private def demo_message_box : Nil
    result = @app.message_box(
      "This message box was shown via App#message_box.",
      detail: "It safely passes {braces} and spaces through - no manual quoting needed.",
      title: "Confirm",
      icon: :question,
      type: :yesnocancel)
    log("message_box -> #{result.inspect}")
  end

  private def demo_choose_color : Nil
    # The } is deliberate - seeing it verbatim in the title bar is the
    # PASS condition, not a mangled string.
    result = @app.choose_color(initial: "#3366ff", title: "Pick a } color (brace is deliberate)")
    log("choose_color -> #{result.inspect}")
  end

  private def demo_popup_menu : Nil
    x = @app.winfo.pointerx
    y = @app.winfo.pointery
    @app.popup_menu(@context_menu, x: x, y: y)
    log("popup_menu shown at #{x},#{y}")
  end

  private def log(message : String) : Nil
    @log.command(:configure, state: :normal)
    @log.command(:insert, :end, "#{message}\n")
    @log.command(:see, :end)
    @log.command(:configure, state: :disabled)
  end
end

demo = DialogsDemo.new
demo.run
