# Interactive example - run with `crystal run examples/goldberg/goldberg_demo.cr`.
# Full teek-ui DSL port of ruby-teek's sample/goldberg_ui.rb - the Rube
# Goldberg canvas animation demo.
#
# Ports goldberg.rb's canvas/physics demo onto the Tryst::UI DSL: the
# control panel below builds real widgets and reactive vars the same way
# any other Tryst::UI app does; the canvas drawing/animation itself is
# driven by GoldbergEngine (see goldberg_engine.cr), which calls straight
# into Handle's canvas item methods (line/oval/polygon/arc/rectangle/
# text/bitmap, CanvasItem's move/coords/scale/configure/...) - no raw
# tcl_eval except the couple of genuine DSL gaps noted inline (a named
# bold font, the initial canvas scroll position), matching the two
# ruby-teek itself calls out.
#
# Drops ruby-teek's own demo_support.rb-driven automated recording/test
# block (TeekDemo) - tooling for ruby-teek's own test/record pipeline
# with no Crystal-side counterpart, same as every other example in this
# port.
require "../../src/tryst/ui"
require "./goldberg_engine"

BG = "cornflowerblue"
FG = "black"

INFO_TEXT = "This is a demonstration of just how complex you can make your animations become. " \
            "Click the ball to start things moving!\n" \
            "\"Man will always find a difficult means to perform a simple task\" - Rube Goldberg"

session = Tryst::UI::Session.new(title: "Tk Goldberg (teek-ui)")

status_var = session.var("Ready")
pause_var = session.var(false)
details_var = session.var(true)
message_var = session.var("\\nWelcome\\nto\\nTryst")
# Float64, not Int32 - a ttk::scale always reports its own -variable as
# a continuous float regardless of -from/-to being whole numbers (no
# -resolution option to snap it the way the classic, non-ttk scale has).
# GoldbergEngine#speed_index does its own rounding off this; the label
# below shows a separately-maintained rounded copy rather than this raw,
# many-decimal value.
speed_var = session.var(5.0)
speed_display_var = session.var("5")
cnt_var = session.var(0)
# String, not Int32 - each one displays either a digit or a blank
# (GoldbergEngine#reset_step writes "") and an Int32-initial Var can't
# hold that second state - see get_step's own comment for why.
step_vars = {} of Int32 => Tryst::UI::Var
(1..26).each { |idx| step_vars[idx] = session.var("0") }

# A bold variant of the default UI font, scoped to the Start button
# only - no DSL equivalent for "inherit the running default font, just
# bold it", and ttk::button doesn't expose -font as a direct widget
# option at all (style-only), so this stays a direct escape-hatch
# font-create + a one-off ttk style, same spirit as goldberg.rb's own
# font-create technique.
session.raw do |app|
  app.tcl_eval("font create GoldbergBold {*}[font configure TkDefaultFont] -weight bold")
  app.tcl_eval("ttk::style configure Bold.TButton -font GoldbergBold")
end

session.menu_bar do |bar|
  bar.menu(label: "File") do |file|
    file.item(:reset_item, label: "Reset")
    file.separator
    file.item(label: "Quit") { session.app.destroy }
  end
  bar.menu(label: "Edit") do |edit|
    edit.checkbox(:edit_details, label: "Details", bind: details_var)
  end
  bar.menu(label: "Help") do |help|
    help.item(:about_item, label: "About")
  end
end

session.row(:layout) do |layout|
  layout.canvas(:board, grow: true, width: 850, height: 700,
    background: BG, highlightthickness: 0, scrollregion: [0, 0, 1000, 1000]) do |board|
    board.overlay(at: :top_right) do
      board.row(gap: 0) do |btns|
        btns.button(:dismiss, text: "Dismiss")
        btns.button(:show_ctrl_btn, text: ">>")
      end
    end
  end

  layout.column(:ctrl, gap: 4, align: :stretch, relief: "ridge", borderwidth: 2, padding: [5, 5]) do |ctrl|
    ctrl.button(:start, text: "Start", style: "Bold.TButton")

    ctrl.checkbox(:pause, text: "Pause", bind: pause_var)
    ctrl.button(:step, text: "Single Step")
    ctrl.button(:bstep, text: "Big Step")
    ctrl.button(:reset, text: "Reset")

    ctrl.column(:details_frame, gap: 0, align: :stretch, relief: "ridge", borderwidth: 2) do |details|
      details.checkbox(:details, text: "Details", bind: details_var)

      details.grid(:detail_grid) do |grid|
        grid.cell(row: 0, col: 0, colspan: 4) do
          grid.label(bind: cnt_var, relief: "solid", borderwidth: 1, background: "white")
        end

        (1..26).each do |idx|
          row = (idx + 1) // 2
          col = ((idx + 1) & 1) * 2
          grid.cell(row: row, col: col) do
            grid.label(text: idx.to_s, anchor: :e, width: 2, relief: "solid", borderwidth: 1, background: "white")
          end
          grid.cell(row: row, col: col + 1) do
            grid.label(bind: step_vars[idx], width: 5, relief: "solid", borderwidth: 1, background: "white")
          end
        end
      end
    end

    ctrl.spacer

    ctrl.text_box(:msg_entry, bind: message_var, justify: :center)

    ctrl.row(:speed_row, gap: 6, align: :center) do |speed_row|
      speed_row.label(text: "Speed:")
      speed_row.label(bind: speed_display_var)
      speed_row.slider(:speed_scale, from: 1, to: 10, bind: speed_var)
    end

    ctrl.button(:about, text: "About")
  end
end

# -- Realize, then build the logic side on the now-live app/canvas ---------

app = session.realize

board = session[:board]
ctrl = session[:ctrl]
show_ctrl_btn = session[:show_ctrl_btn]

engine = GoldbergEngine.new(session, board, status_var, pause_var, details_var,
  message_var, speed_var, cnt_var, step_vars)

# The info message, in the canvas's own top-left corner. A classic (not
# ttk) label, matching goldberg.rb's own choice here - ttk::label accepts
# -background without error, but under macOS's Aqua theme it's silently
# ignored at render time, leaving the theme's own light background
# showing through instead of matching the canvas. A plain Tk label has no
# theme to fight, so -bg always applies. No DSL widget type for a
# non-ttk label, so this is a direct escape-hatch creation + place,
# reusing the same anchor math ui.overlay's own :top_left anchor uses.
board_path = board.path
msg_path = "#{board_path}.msg"
app.create_widget(:label, msg_path, background: BG, foreground: "white",
  font: "Arial 10", wraplength: 600, justify: :left, text: INFO_TEXT)
app.command(:place, [msg_path] of Tryst::TclArgValue,
  {"in" => board_path, "relx" => 0, "rely" => 0, "anchor" => "nw"} of String => Tryst::TclArgValue)

# No DSL equivalent for an initial canvas scroll position - a one-line
# escape hatch, same as goldberg.rb's own `yview moveto`.
app.tcl_invoke(board_path, "yview", "moveto", "0.05")

# The control panel starts collapsed, exactly like goldberg.rb's own
# @ctrl (built but never packed until the >> button first shows it) -
# done right after realize, before anything is painted, so there's no
# visible flash of it being shown then immediately hidden.
app.command(:pack, :forget, ctrl.path)

# -- Wire events ------------------------------------------------------------

# Keeps the speed readout an integer while the ttk::scale itself keeps
# reporting a continuous float - see speed_var's own comment above.
speed_var.on_change { |value| speed_display_var.value = value.as(Float64).round.to_i.to_s }

session[:dismiss].on_click { app.destroy }
show_ctrl_btn.on_click do
  if app.winfo.ismapped?(ctrl.path)
    app.command(:pack, :forget, ctrl.path)
    show_ctrl_btn.configure(text: ">>")
  else
    app.command(:pack, ctrl.path, side: :right, fill: :both, ipady: 5)
    show_ctrl_btn.configure(text: "<<")
  end
end

session[:start].on_click { engine.do_button(0) }
session[:pause].on_click { engine.do_button(1) }
session[:step].on_click { engine.do_button(2) }
session[:bstep].on_click { engine.do_button(4) }
session[:reset].on_click { engine.do_button(3) }
session[:details].on_click { engine.active_gui }
session[:about].on_click { engine.about }

session[:reset_item].on_action { engine.reset }
session[:edit_details].on_click { engine.active_gui }
session[:about_item].on_action { engine.about }

app.bring_to_front
app.mainloop
