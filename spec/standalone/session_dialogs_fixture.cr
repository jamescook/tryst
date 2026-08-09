require "../../src/teek/ui"

# Standalone verification that Session's dialog passthroughs forward
# every option to the App wrapper underneath, under the right Tk flag,
# with the right return value coming back.
#
# Real dialogs block waiting for a human, so - exactly like the App-level
# dialog coverage in spec/support/tk_cases.cr - each one stubs the
# underlying Tcl command (tk_getOpenFile and friends) to capture the args
# it was actually invoked with and return a canned result. Nothing pops
# up, and the assertion is on the real Tcl call the wrapper built.
#
# Needs its own subprocess (see spec/teek/ui/session_realtk_spec.cr)
# because Session#realize always constructs a brand-new Teek::App, which
# the shared tk_worker can't host.

# Parses a captured "-flag1 value1 -flag2 value2" Tcl arg list into a
# Hash, so assertions don't depend on the order a wrapper happens to
# build its flags in. Mirrors tk_cases.cr's own helper of the same name.
private def tcl_flag_hash(list_str : String) : Hash(String, String)
  parts = Teek.split_list(list_str)
  hash = {} of String => String
  parts.each_slice(2) { |pair| hash[pair[0]] = pair[1] }
  hash
end

private def assert_flags(app, expected : Hash(String, String), label : String) : Nil
  captured = tcl_flag_hash(app.tcl_eval("set ::last_call"))
  raise "#{label}: expected flags #{expected}, got #{captured}" unless captured == expected
end

session = Teek::UI.app(title: "session dialogs fixture") do |builder|
  builder.label(:hello, text: "Hello")
end

app = session.realize

# Case 1: open_file forwards every option, and returns the path - one
# containing both a space and braces, to prove the value travels as a
# real Tcl value rather than through string interpolation.
app.tcl_eval(<<-TCL)
  proc tk_getOpenFile {args} {
    set ::last_call $args
    return {/tmp/some dir/a file {with braces}.png}
  }
  TCL

opened = session.open_file(title: "Pick a } file", initialdir: "/tmp/some dir")
raise "open_file: got #{opened.inspect}" unless opened == "/tmp/some dir/a file {with braces}.png"
assert_flags(app, {"-title" => "Pick a } file", "-initialdir" => "/tmp/some dir"}, "open_file")

# Case 2: a cancelled dialog (empty Tk result) comes back as nil, not "".
app.tcl_eval("proc tk_getOpenFile {args} { set ::last_call $args; return {} }")
raise "open_file cancel: expected nil, got #{session.open_file.inspect}" unless session.open_file.nil?

# Case 3: multiple: splits Tk's list result into an array.
app.tcl_eval(<<-TCL)
  proc tk_getOpenFile {args} {
    set ::last_call $args
    return {{/tmp/a file.png} /tmp/b.png}
  }
  TCL

many = session.open_file(multiple: true)
raise "open_file multiple: got #{many.inspect}" unless many == ["/tmp/a file.png", "/tmp/b.png"]

# Case 4: save_file, including the two options open_file doesn't have.
app.tcl_eval(<<-TCL)
  proc tk_getSaveFile {args} {
    set ::last_call $args
    return {/tmp/out.txt}
  }
  TCL

saved = session.save_file(title: "Save as", initialfile: "my file.txt",
  defaultextension: ".txt", confirmoverwrite: false)
raise "save_file: got #{saved.inspect}" unless saved == "/tmp/out.txt"
assert_flags(app, {
  "-initialfile"      => "my file.txt",
  "-title"            => "Save as",
  "-defaultextension" => ".txt",
  "-confirmoverwrite" => "0",
}, "save_file")

# Case 5: message forwards its options and maps Tk's button string back
# to a Symbol.
app.tcl_eval(<<-TCL)
  proc tk_messageBox {args} {
    set ::last_call $args
    return {yes}
  }
  TCL

answer = session.message("Sure?", title: "Confirm", detail: "Cannot be undone",
  icon: :question, type: :yesno, default: :no)
raise "message: expected :yes, got #{answer.inspect}" unless answer == :yes
assert_flags(app, {
  "-message" => "Sure?",
  "-title"   => "Confirm",
  "-detail"  => "Cannot be undone",
  "-icon"    => "question",
  "-type"    => "yesno",
  "-default" => "no",
}, "message")

# Case 6: choose_color.
app.tcl_eval(<<-TCL)
  proc tk_chooseColor {args} {
    set ::last_call $args
    return {#aabbcc}
  }
  TCL

color = session.choose_color(initial: "#112233", title: "Pick")
raise "choose_color: got #{color.inspect}" unless color == "#aabbcc"
assert_flags(app, {"-initialcolor" => "#112233", "-title" => "Pick"}, "choose_color")

# Case 7: choose_dir, with the boolean-flag option.
app.tcl_eval(<<-TCL)
  proc tk_chooseDirectory {args} {
    set ::last_call $args
    return {/tmp/dir}
  }
  TCL

dir = session.choose_dir(initialdir: "/tmp", mustexist: true, title: "Folder")
raise "choose_dir: got #{dir.inspect}" unless dir == "/tmp/dir"
assert_flags(app, {"-initialdir" => "/tmp", "-mustexist" => "1", "-title" => "Folder"}, "choose_dir")

app.destroy
puts "OK"
