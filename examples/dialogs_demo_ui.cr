# Interactive example - run with `crystal run examples/dialogs_demo_ui.cr`.
#
# The Tryst::UI DSL twin of examples/dialogs_demo.cr, and worth reading
# next to it. They are NOT two spellings of the same calls: this one goes
# through Session's dialog helpers (#open_file/#save_file/#message/
# #choose_color/#choose_dir), while the original calls App's wrappers
# (#choose_open_file/#choose_save_file/#message_box/#choose_color)
# directly. Session's are thin passthroughs that add a realize check, so
# the two files cover two different code paths - which is the whole reason
# both exist. Keep both.
#
# Also a manual test harness, not a "real" app: verification is that it
# compiles and that a human clicks each button once. Nothing here is
# automatically verified, and nothing should be - these open native modal
# dialogs that only a person can answer.
#
# Same hazards as the original on purpose: titles with spaces, a default
# filename with a space in it, a `}` inside a title, and multi-pattern
# filetypes. If any of those come back mangled, the option quoting is
# wrong somewhere underneath.
require "../src/tryst/ui"

IMAGE_FILETYPES = [
  {"Images", [".png", ".jpg", ".gif"]},
  {"Text Files", ".txt"},
  {"All Files", "*"},
]

session = Tryst::UI.app(title: "Dialog Wrappers Demo (UI DSL)", geometry: "520x420") do |builder|
  # Every dialog reports back through this one var, bound to the label at
  # the bottom - no widget reconfiguring by hand anywhere in this file.
  # Setting .value is the whole of "show the result".
  result = builder.var("(nothing chosen yet - click a button)")

  # Declared before the widget that pops it up, which is fine: a menu
  # handle passed to #on_right_click has its path read lazily, when a
  # click actually fires, not at wiring time.
  menu = builder.context_menu(:ctx) do |entries|
    entries.item(label: "Say Hello") { result.value = "context menu -> Say Hello" }
    entries.item(label: "Say Goodbye") { result.value = "context menu -> Say Goodbye" }
    entries.separator
    entries.item(label: "(just closes the menu)") { }
  end

  builder.column(gap: 6, pad: 8, align: :stretch) do |col|
    col.label(
      text: "Each button calls a Session dialog helper. Try options with " \
            "spaces in them\n(a filename, a title...) to confirm nothing " \
            "gets mangled.\nRight-click the result area below for the " \
            "context menu.",
      justify: :left)

    col.divider

    col.button(text: "Open File...").on_action do
      chosen = builder.open_file(
        title: "Choose a file to open (try one with spaces in the name)",
        filetypes: IMAGE_FILETYPES)
      result.value = "open_file -> #{chosen.inspect}"
    end

    col.button(text: "Save File...").on_action do
      chosen = builder.save_file(
        title: "Choose where to save",
        initialfile: "my file.txt",
        filetypes: [{"Text Files", ".txt"}, {"All Files", "*"}])
      result.value = "save_file -> #{chosen.inspect}"
    end

    # The original harness has no directory case - App#choose_dir existed
    # but went unexercised. Session#choose_dir is part of the same
    # passthrough surface, so it gets a button here.
    col.button(text: "Choose Directory...").on_action do
      chosen = builder.choose_dir(title: "Pick any directory", mustexist: true)
      result.value = "choose_dir -> #{chosen.inspect}"
    end

    col.button(text: "Message Box...").on_action do
      answer = builder.message(
        "This message box was shown via Session#message.",
        detail: "It safely passes {braces} and spaces through - no manual quoting needed.",
        title: "Confirm",
        icon: :question,
        type: :yesnocancel)
      result.value = "message -> #{answer.inspect}"
    end

    col.button(text: "Choose Color...").on_action do
      # The } is deliberate, and seeing it verbatim in the dialog's title
      # bar is the PASS condition - it means the brace reached Tk quoted
      # rather than being read as the end of a Tcl group.
      chosen = builder.choose_color(initial: "#3366ff", title: "Pick a } color (brace is deliberate)")
      result.value = "choose_color -> #{chosen.inspect}"
    end

    col.divider

    # Bound to the var, so this label never gets configured directly.
    # on_right_click(menu) pops the context menu at the click position and
    # binds every platform's spelling of a right click - Button-3 on
    # Linux/Windows, Button-2 and Control-Button-1 on macOS.
    col.label(:result, bind: result, justify: :left, wraplength: 460,
      relief: :sunken, padding: 6)
      .on_right_click(menu)
  end

  # No focus incantation here: #run brings the window to the front for us
  # (App#bring_to_front), and does it WITHOUT leaving the window pinned
  # above everything - which is what used to make every dialog below open
  # behind this window.
end

session.run
