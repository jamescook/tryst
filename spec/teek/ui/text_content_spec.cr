require "../../spec_helper"
require "../../support/fake_app"
require "../../support/widget_dsl_harness"
require "../../../src/teek/ui/realizer"

# Headless tests for Teek::UI::TextContent - the exact Tk commands each
# method builds, against FakeApp. Real-Tk confirmation that those commands
# do what they claim (text really inserted and read back, a read-only
# widget really mutated, a format click really firing) lives in the
# tk_test cases in spec/support/tk_cases.cr.
#
# Mirrors ruby-teek's teek-ui/test/test_text_content.rb, which is entirely
# real-Tk - so this file is new coverage of the same surface one tier down.

# A TextContent on a bare path, with the widget's -state staged as
# whatever `cget -state` should answer. FakeApp hands the same result back
# for every command, so a spec that needs a specific reply sets it itself.
private def text_content(state : String = "normal") : {FakeApp, Teek::UI::TextContent}
  app = FakeApp.new
  app.command_result = state
  {app, Teek::UI::TextContent.new(app, ".notes")}
end

# Every command sent to the text widget as [subcommand, args...], dropping
# the -state reads/writes #mutate makes on its own (asserted separately).
private def sent(app) : Array(Array(Teek::TclArgValue))
  app.calls.select { |call| call.cmd == ".notes" }.map(&.args)
    .reject { |args| args.first? == :cget || args.first? == :configure }
end

describe Teek::UI::TextContent do
  describe "content" do
    it "insert places text at an index" do
      app, text = text_content
      text.insert("1.0", "hello")

      sent(app).should eq([[:insert, "1.0", "hello"] of Teek::TclArgValue])
    end

    it "insert applies any trailing format names to what it inserted" do
      app, text = text_content
      text.insert(:end, "boom", :error, "loud")

      sent(app).should eq([[:insert, "end", "boom", :error, "loud"] of Teek::TclArgValue])
    end

    it "get reads a range, the whole buffer by default" do
      app, text = text_content
      text.get
      text.get("2.0", :end)

      sent(app).should eq([
        [:get, "1.0", "end"] of Teek::TclArgValue,
        [:get, "2.0", "end"] of Teek::TclArgValue,
      ])
    end

    it "delete takes a range, or one character when given no end" do
      app, text = text_content
      text.delete("1.0", "2.0")
      text.delete("1.0")

      sent(app).should eq([
        [:delete, "1.0", "2.0"] of Teek::TclArgValue,
        [:delete, "1.0"] of Teek::TclArgValue,
      ])
    end

    it "replace swaps a range for new text in one call" do
      app, text = text_content
      text.replace("1.0", "1.5", "howdy")

      sent(app).should eq([[:replace, "1.0", "1.5", "howdy"] of Teek::TclArgValue])
    end

    # Tk keeps a newline at "end" that was never typed, so asking for the
    # buffer verbatim would hand back one the caller never put there.
    it "value asks for the buffer without Tk's synthetic trailing newline" do
      app, text = text_content
      text.value

      sent(app).should eq([[:get, "1.0", "end-1c"] of Teek::TclArgValue])
    end

    it "value= empties the buffer before inserting the replacement" do
      app, text = text_content
      text.value = "fresh"

      sent(app).should eq([
        [:delete, "1.0", "end"] of Teek::TclArgValue,
        [:insert, "1.0", "fresh"] of Teek::TclArgValue,
      ])
    end

    it "clear deletes everything" do
      app, text = text_content
      text.clear

      sent(app).should eq([[:delete, "1.0", "end"] of Teek::TclArgValue])
    end
  end

  describe "indices" do
    it ":end and :cursor stand in for Tk's own end and insert" do
      app, text = text_content
      text.insert(:end, "a")
      text.insert(:cursor, "b")

      sent(app).map(&.[](1)).should eq(["end", "insert"] of Teek::TclArgValue)
    end

    # The point of not wrapping indices in a type of their own: Tk's whole
    # index grammar stays available without this class knowing any of it.
    it "any other index is passed through verbatim" do
      app, text = text_content
      ["1.0", "end-1c", "insert +1 line", "sel.first", "@12,34", "my_marker"].each do |spec|
        text.scroll_to(spec)
      end

      sent(app).map(&.[](1)).should eq(
        ["1.0", "end-1c", "insert +1 line", "sel.first", "@12,34", "my_marker"] of Teek::TclArgValue)
    end
  end

  # Tk silently no-ops a mutation against a disabled text widget, so every
  # mutating method lifts the state and puts it back.
  describe "mutating a read-only widget" do
    it "lifts the state for the call and restores it after" do
      app, text = text_content(state: "disabled")
      text.insert("1.0", "logged")

      states = app.calls.select { |call| call.args.first? == :configure }.map(&.kwargs)
      states.should eq([
        {"state" => "normal"} of String => Teek::TclArgValue,
        {"state" => "disabled"} of String => Teek::TclArgValue,
      ])
    end

    it "leaves an editable widget's state alone entirely" do
      app, text = text_content(state: "normal")
      text.insert("1.0", "typed")

      app.calls.select { |call| call.args.first? == :configure }.should be_empty
    end

    # That the state is restored even when the mutation RAISES needs a
    # command that really fails, which a plain recorder can't be - it's a
    # tk_test case in spec/support/tk_cases.cr instead.
    it "covers every mutating method, not just insert" do
      # value= issues two commands inside ONE lift, rather than lifting
      # and restoring around each - so the state is written twice, not
      # four times.
      app, text = text_content(state: "disabled")
      text.value = "replaced"

      states = app.calls.select { |call| call.args.first? == :configure }.map(&.kwargs)
      states.should eq([
        {"state" => "normal"} of String => Teek::TclArgValue,
        {"state" => "disabled"} of String => Teek::TclArgValue,
      ])
    end
  end

  describe "formats" do
    it "format defines display properties under a name" do
      app, text = text_content
      text.format(:error, foreground: "red", underline: true)

      call = app.calls.find { |call| call.args.first? == :tag }.should_not be_nil
      call.args.should eq([:tag, :configure, :error] of Teek::TclArgValue)
      call.kwargs.should eq({"foreground" => "red", "underline" => true} of String => Teek::TclArgValue)
    end

    it "apply_format applies one to a range, clear_format takes it off again" do
      app, text = text_content
      text.apply_format(:error, "1.0", "1.5")
      text.clear_format(:error, "1.0", :end)

      sent(app).should eq([
        [:tag, :add, :error, "1.0", "1.5"] of Teek::TclArgValue,
        [:tag, :remove, :error, "1.0", "end"] of Teek::TclArgValue,
      ])
    end

    it "delete_format removes the definition itself" do
      app, text = text_content
      text.delete_format(:error)

      sent(app).should eq([[:tag, :delete, :error] of Teek::TclArgValue])
    end

    it "format_ranges splits Tk's flat list of index pairs" do
      app, text = text_content
      app.command_result = "1.0 1.5 2.3 2.8"

      text.format_ranges(:error).should eq(["1.0", "1.5", "2.3", "2.8"])
    end

    it "on_format_click binds a left click on the format, callback and all" do
      app, text = text_content
      text.on_format_click(:link) { }

      call = app.calls.last
      call.args.first(4).should eq([:tag, :bind, :link, "<Button-1>"] of Teek::TclArgValue)
      call.args[4].should be_a(Proc(Array(String), Teek::CallbackSignal, Nil))
    end

    it "on_format takes any event pattern, with or without the angle brackets" do
      app, text = text_content
      text.on_format(:link, "Double-Button-1") { }
      text.on_format(:link, "<Enter>") { }

      app.calls.map { |call| call.args[3]? }.should eq(["<Double-Button-1>", "<Enter>"] of Teek::TclArgValue)
    end

    # `tag bind` rather than a raw tcl_eval is what puts the callback under
    # teek's own leak-safe reconcile - see TagBindInterceptor.
    it "routes format bindings through the widget's own tag bind" do
      app, text = text_content
      text.on_format_click(:link) { }

      app.calls.last.cmd.should eq(".notes")
      app.calls.last.args.first(2).should eq([:tag, :bind] of Teek::TclArgValue)
    end
  end

  describe "markers" do
    it "add_marker places one, remove_marker unsets it" do
      app, text = text_content
      text.add_marker(:here, at: "1.0")
      text.remove_marker(:here)

      sent(app).should eq([
        [:mark, :set, :here, "1.0"] of Teek::TclArgValue,
        [:mark, :unset, :here] of Teek::TclArgValue,
      ])
    end

    it "markers lists what Tk reports" do
      app, text = text_content
      app.command_result = "insert current here"

      text.markers.should eq(["insert", "current", "here"])
    end

    it "mark_gravity reads with no direction and sets with one" do
      app, text = text_content
      text.mark_gravity(:here)
      text.mark_gravity(:here, :left)

      sent(app).should eq([
        [:mark, :gravity, :here] of Teek::TclArgValue,
        [:mark, :gravity, :here, :left] of Teek::TclArgValue,
      ])
    end
  end

  describe "search" do
    it "searches forward from the cursor by default" do
      app, text = text_content
      app.command_result = "3.7"

      text.search("needle").should eq("3.7")
      sent(app).should eq([[:search, "--", "needle", "insert", "end"] of Teek::TclArgValue])
    end

    it "answers nil rather than an empty string when there's no match" do
      app, text = text_content
      app.command_result = ""

      text.search("needle").should be_nil
    end

    it "forwards each switch, before the -- that ends them" do
      app, text = text_content
      text.search("-dash", from: "1.0", to: :end, backwards: true, regexp: true, nocase: true)

      sent(app).should eq([
        [:search, "-backward", "-regexp", "-nocase", "--", "-dash", "1.0", "end"] of Teek::TclArgValue,
      ])
    end
  end

  describe "view, cursor and state" do
    it "scroll_to scrolls an index into view" do
      app, text = text_content
      text.scroll_to("50.0")

      sent(app).should eq([[:see, "50.0"] of Teek::TclArgValue])
    end

    it "index canonicalises an index expression" do
      app, text = text_content
      app.command_result = "2.0"

      text.index("insert +1 line").should eq("2.0")
      sent(app).should eq([[:index, "insert +1 line"] of Teek::TclArgValue])
    end

    it "cursor reads the insert mark, cursor= moves it" do
      app, text = text_content
      app.command_result = "4.2"

      text.cursor.should eq("4.2")
      text.cursor = "1.0"

      sent(app).should eq([
        [:index, "insert"] of Teek::TclArgValue,
        [:mark, :set, "insert", "1.0"] of Teek::TclArgValue,
      ])
    end

    it "read_only reports whether Tk's own -state is disabled" do
      disabled_app, disabled = text_content(state: "disabled")
      normal_app, normal = text_content(state: "normal")

      disabled.read_only.should be_true
      normal.read_only.should be_false
      disabled_app.calls.last.args.should eq([:cget, "-state"] of Teek::TclArgValue)
      normal_app.calls.size.should eq(1)
    end

    it "read_only= drives that same -state" do
      app, text = text_content
      text.read_only = true
      text.read_only = false

      app.calls.map(&.kwargs).should eq([
        {"state" => "disabled"} of String => Teek::TclArgValue,
        {"state" => "normal"} of String => Teek::TclArgValue,
      ])
    end
  end

  describe "embedded images" do
    it "insert_image embeds one in the text flow" do
      app, text = text_content
      image = Teek::UI::Image.new("teek_ui_image_1", ".notes")

      text.insert_image("1.0", image: image)

      call = app.calls.find { |call| call.args.first? == :image }.should_not be_nil
      call.args.should eq([:image, :create, "1.0"] of Teek::TclArgValue)
      call.kwargs.should eq({"image" => "teek_ui_image_1"} of String => Teek::TclArgValue)
    end

    # A raw Teek::Photo works too - it needs a live App to exist at all,
    # so that arm of the union is a tk_test case in
    # spec/support/tk_cases.cr.
    it "takes a plain Tcl image name as well" do
      app, text = text_content
      text.insert_image(:end, image: "some_tcl_image")

      app.calls.find { |call| call.args.first? == :image }
        .should_not(be_nil).kwargs.should eq({"image" => "some_tcl_image"} of String => Teek::TclArgValue)
    end

    it "lifts a read-only widget like the other mutators" do
      app, text = text_content(state: "disabled")
      text.insert_image("1.0", image: "some_image")

      states = app.calls.select { |call| call.args.first? == :configure }.map(&.kwargs)
      states.should eq([
        {"state" => "normal"} of String => Teek::TclArgValue,
        {"state" => "disabled"} of String => Teek::TclArgValue,
      ])
    end
  end

  # Tk's own spelling of the same methods, for code written against the Tk
  # manual page. Asserted as sending byte-identical commands rather than
  # by re-testing each behaviour.
  describe "the Tk-named delegations" do
    it "send exactly what the friendly names send" do
      friendly_app, friendly = text_content
      friendly.format(:e, foreground: "red")
      friendly.apply_format(:e, "1.0", "1.5")
      friendly.clear_format(:e, "1.0", "1.5")
      friendly.format_ranges(:e)
      friendly.delete_format(:e)
      friendly.add_marker(:m, at: "1.0")
      friendly.markers
      friendly.remove_marker(:m)
      friendly.scroll_to("1.0")
      friendly.insert_image("1.0", image: "img")

      tk_app, tk = text_content
      tk.tag_configure(:e, foreground: "red")
      tk.tag_add(:e, "1.0", "1.5")
      tk.tag_remove(:e, "1.0", "1.5")
      tk.tag_ranges(:e)
      tk.tag_delete(:e)
      tk.mark_set(:m, at: "1.0")
      tk.mark_names
      tk.mark_unset(:m)
      tk.see("1.0")
      tk.image_create("1.0", image: "img")

      tk_app.calls.should eq(friendly_app.calls)
    end

    it "bind the same way too" do
      click_app, click = text_content
      click.on_format_click(:link) { }
      click.on_format(:link, "Enter") { }

      tk_app, tk = text_content
      tk.on_tag_click(:link) { }
      tk.on_tag(:link, "Enter") { }

      # The callbacks themselves are different Proc objects, so compare
      # everything up to them.
      tk_app.calls.map(&.args.first(4))
        .should eq(click_app.calls.map(&.args.first(4)))
    end
  end
end

describe "Handle#text_content" do
  it "hands back a TextContent for a realized text_area" do
    session = WidgetDslHarness.new
    handle = session.text_area(:notes)

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    handle.text_content.should be_a(Teek::UI::TextContent)
  end

  # The text widget itself, not the frame the auto-scrollbar wraps it in.
  it "addresses the text widget inside the scrollbar wrapper" do
    session = WidgetDslHarness.new
    handle = session.text_area(:notes)

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize
    handle.text_content.insert("1.0", "hi")

    app.calls.last.cmd.should eq(".notes.widget")
  end

  it "raises before realize, like every other live accessor" do
    session = WidgetDslHarness.new
    handle = session.text_area(:notes)

    expect_raises(Teek::UI::NotRealizedError) { handle.text_content }
  end

  it "raises a clear error on a handle that isn't a text_area" do
    session = WidgetDslHarness.new
    handle = session.text_box(:query)

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    expect_raises(ArgumentError, /text_area/) { handle.text_content }
  end
end
