require "../tk_test_registry"

# Parses a Tcl arg list of the form "-flag1 value1 -flag2 value2 ..."
# (e.g. a stubbed dialog command's captured $args) into a Hash, so
# dialog-test assertions don't depend on the order a wrapper method
# happens to build its flags in. Mirrors ruby-tryst's own TestContext#tcl_flag_hash
# (test/tryst_test_worker.rb) - pure Tcl-list parsing, no App/Tk needed.
private def tcl_flag_hash(list_str : String) : Hash(String, String)
  parts = Tryst.split_list(list_str)
  hash = {} of String => String
  parts.each_slice(2) { |pair| hash[pair[0]] = pair[1] }
  hash
end

tk_test "clipboard.set followed by .get round-trips the text" do |app|
  app.clipboard.set("hello world")
  raise "expected 'hello world'" unless app.clipboard.get == "hello world"
end

tk_test "a second clipboard.set replaces the contents, not appends to them" do |app|
  app.clipboard.set("first")
  app.clipboard.set("second")
  raise "expected 'second'" unless app.clipboard.get == "second"
end

tk_test "clipboard.set treats a leading hyphen as literal data, not an append option" do |app|
  app.clipboard.set("-not-an-option")
  raise "expected '-not-an-option'" unless app.clipboard.get == "-not-an-option"
end

tk_test "clipboard.get returns nil rather than raising when nothing has been set" do |app|
  app.clipboard.clear
  raise "expected nil" unless app.clipboard.get.nil?
end

tk_test "clipboard.clear empties a clipboard that already had content" do |app|
  app.clipboard.set("something")
  app.clipboard.clear
  raise "expected nil" unless app.clipboard.get.nil?
end

# Real dialogs block waiting for a human, so these stub the underlying Tcl
# command (tk_getOpenFile, etc.) to capture the args it was actually
# invoked with and return a canned result - that proves the wrapper
# builds its Tcl call via tcl_invoke (no string interpolation), with
# options containing spaces/braces passed through intact, without ever
# popping up a real dialog.
tk_test "choose_open_file passes options with spaces/braces safely and returns the path" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_getOpenFile {args} {
      set ::last_call $args
      return {/tmp/some dir/a file {with braces}.png}
    }
    TCL

  result = app.choose_open_file(title: "Pick a } file", initialdir: "/tmp/some dir")

  raise "expected the stubbed path" unless result == "/tmp/some dir/a file {with braces}.png"
  captured = tcl_flag_hash(app.tcl_eval("set ::last_call"))
  expected = {"-title" => "Pick a } file", "-initialdir" => "/tmp/some dir"}
  raise "expected #{expected}, got #{captured}" unless captured == expected
end

tk_test "choose_open_file returns nil when the user cancels (empty Tk result)" do |app|
  app.tcl_eval("proc tk_getOpenFile {args} { return {} }")
  raise "expected nil" unless app.choose_open_file.nil?
end

tk_test "choose_open_file with multiple: true splits Tk's list result into an array" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_getOpenFile {args} {
      return {{/tmp/a file.png} /tmp/b.png}
    }
    TCL

  result = app.choose_open_file(multiple: true)

  raise "expected the split array, got #{result.inspect}" unless result == ["/tmp/a file.png", "/tmp/b.png"]
end

tk_test "choose_open_file builds a correctly nested Tcl list for filetypes" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_getOpenFile {args} {
      set ::last_call $args
      return {}
    }
    TCL

  app.choose_open_file(filetypes: [{"PNG Images", ".png"}, {"All Files", "*"}])

  captured = app.split_list(app.tcl_eval("set ::last_call"))
  filetypes_arg = captured[captured.index!("-filetypes") + 1]
  entries = app.split_list(filetypes_arg)
  raise "expected PNG entry" unless app.split_list(entries[0]) == ["PNG Images", ".png"]
  raise "expected All Files entry" unless app.split_list(entries[1]) == ["All Files", "*"]
end

tk_test "choose_open_file filetypes accepts an array of extensions per entry" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_getOpenFile {args} {
      set ::last_call $args
      return {}
    }
    TCL

  app.choose_open_file(filetypes: [{"Images", [".png", ".jpg"]}])

  captured = app.split_list(app.tcl_eval("set ::last_call"))
  filetypes_arg = captured[captured.index!("-filetypes") + 1]
  entry = app.split_list(app.split_list(filetypes_arg)[0])
  raise "expected 'Images'" unless entry[0] == "Images"
  raise "expected extensions array" unless app.split_list(entry[1]) == [".png", ".jpg"]
end

tk_test "choose_save_file passes options safely and returns the path" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_getSaveFile {args} {
      set ::last_call $args
      return {/tmp/save dir/out.png}
    }
    TCL

  result = app.choose_save_file(title: "Save As", initialfile: "my file.png", defaultextension: ".png")

  raise "expected the stubbed path" unless result == "/tmp/save dir/out.png"
  captured = tcl_flag_hash(app.tcl_eval("set ::last_call"))
  expected = {"-title" => "Save As", "-initialfile" => "my file.png", "-defaultextension" => ".png"}
  raise "expected #{expected}, got #{captured}" unless captured == expected
end

tk_test "choose_save_file returns nil when the user cancels" do |app|
  app.tcl_eval("proc tk_getSaveFile {args} { return {} }")
  raise "expected nil" unless app.choose_save_file.nil?
end

tk_test "message_box passes options safely and returns the pressed button as a symbol" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_messageBox {args} {
      set ::last_call $args
      return {yes}
    }
    TCL

  result = app.message_box(message: "Delete {this}?", title: "Confirm", icon: :warning, type: :yesno)

  raise "expected :yes, got #{result.inspect}" unless result == :yes
  captured = tcl_flag_hash(app.tcl_eval("set ::last_call"))
  expected = {"-message" => "Delete {this}?", "-title" => "Confirm", "-icon" => "warning", "-type" => "yesno"}
  raise "expected #{expected}, got #{captured}" unless captured == expected
end

tk_test "choose_color passes options safely and returns the chosen color" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_chooseColor {args} {
      set ::last_call $args
      return {#ff0080}
    }
    TCL

  result = app.choose_color(initial: "#ff0000", title: "Pick a } color")

  raise "expected '#ff0080'" unless result == "#ff0080"
  captured = tcl_flag_hash(app.tcl_eval("set ::last_call"))
  expected = {"-initialcolor" => "#ff0000", "-title" => "Pick a } color"}
  raise "expected #{expected}, got #{captured}" unless captured == expected
end

tk_test "choose_color returns nil when the user cancels" do |app|
  app.tcl_eval("proc tk_chooseColor {args} { return {} }")
  raise "expected nil" unless app.choose_color.nil?
end

tk_test "choose_dir passes options safely and returns the chosen directory" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_chooseDirectory {args} {
      set ::last_call $args
      return {/tmp/some dir/with {braces}}
    }
    TCL

  result = app.choose_dir(title: "Pick a } folder", initialdir: "/tmp/some dir")

  raise "expected the stubbed path" unless result == "/tmp/some dir/with {braces}"
  captured = tcl_flag_hash(app.tcl_eval("set ::last_call"))
  expected = {"-title" => "Pick a } folder", "-initialdir" => "/tmp/some dir"}
  raise "expected #{expected}, got #{captured}" unless captured == expected
end

tk_test "choose_dir returns nil when the user cancels (empty Tk result)" do |app|
  app.tcl_eval("proc tk_chooseDirectory {args} { return {} }")
  raise "expected nil" unless app.choose_dir.nil?
end

tk_test "choose_dir's mustexist: only appears on the wire when true (Tk's own default is false)" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_chooseDirectory {args} {
      set ::last_call $args
      return {}
    }
    TCL

  app.choose_dir
  raise "did not expect -mustexist" if app.tcl_eval("set ::last_call").includes?("-mustexist")

  app.choose_dir(mustexist: true)
  captured = tcl_flag_hash(app.tcl_eval("set ::last_call"))
  raise "expected -mustexist 1" unless captured["-mustexist"] == "1"
end

tk_test "popup_menu invokes tk_popup with the menu path and screen coordinates" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_popup {args} {
      set ::last_call $args
    }
    TCL
  menu = app.menu(".popup_test_menu")

  app.popup_menu(menu, x: 100, y: 200)

  captured = app.split_list(app.tcl_eval("set ::last_call"))
  raise "expected [#{menu}, 100, 200], got #{captured.inspect}" unless captured == [menu.to_s, "100", "200"]
end

tk_test "popup_menu passes an explicit active entry when given" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_popup {args} {
      set ::last_call $args
    }
    TCL
  menu = app.menu(".popup_test_menu2")

  app.popup_menu(menu, x: 10, y: 20, entry: 1)

  captured = app.split_list(app.tcl_eval("set ::last_call"))
  raise "expected [#{menu}, 10, 20, 1], got #{captured.inspect}" unless captured == [menu.to_s, "10", "20", "1"]
end
