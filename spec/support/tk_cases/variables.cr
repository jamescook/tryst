require "../tk_test_registry"

tk_test "set_variable/get_variable round-trip" do |app|
  app.set_variable("myvar", "hello")
  raise "expected 'hello'" unless app.get_variable("myvar") == "hello"
end

tk_test "set_variable overwrites an existing value" do |app|
  app.set_variable("x", "first")
  app.set_variable("x", "second")
  raise "expected 'second'" unless app.get_variable("x") == "second"
end

tk_test "get_variable on a nonexistent variable raises" do |app|
  begin
    app.get_variable("does_not_exist_xyz")
    raise "expected TclError, got no exception"
  rescue Tryst::TclError
  end
end

tk_test "a variable works with widget textvariable" do |app|
  app.set_variable("lbl_text", "initial")
  app.command("ttk::label", ".lbl_var", textvariable: :lbl_text)

  raise "expected 'initial'" unless app.tcl_eval(".lbl_var cget -text") == "initial"

  app.set_variable("lbl_text", "updated")
  raise "expected 'updated'" unless app.tcl_eval(".lbl_var cget -text") == "updated"
end

tk_test "set_variable returns the value" do |app|
  raise "expected '42'" unless app.set_variable("rv", "42") == "42"
end

# set_variable/get_variable route through Interp#tcl_set_var/tcl_get_var
# (Tcl_SetVar/Tcl_GetVar directly) rather than building a "set name
# {value}" string and re-parsing it through the Tcl interpreter, so none
# of these need any escaping on the Crystal side.
tk_test "a value with an unbalanced closing brace round-trips" do |app|
  app.set_variable("v_close_brace", "a}b")
  raise "expected round-trip" unless app.get_variable("v_close_brace") == "a}b"
end

tk_test "a value with an unbalanced opening brace round-trips" do |app|
  app.set_variable("v_open_brace", "a{b")
  raise "expected round-trip" unless app.get_variable("v_open_brace") == "a{b"
end

tk_test "a value ending with a backslash round-trips" do |app|
  app.set_variable("v_trailing_bs", "C:\\path\\")
  raise "expected round-trip" unless app.get_variable("v_trailing_bs") == "C:\\path\\"
end

tk_test "a value containing a dollar sign is not variable-substituted" do |app|
  app.set_variable("some_other_var", "SHOULD_NOT_APPEAR")
  app.set_variable("v_dollar", "$some_other_var")
  raise "expected literal $some_other_var" unless app.get_variable("v_dollar") == "$some_other_var"
end

tk_test "a value containing brackets is not command-substituted" do |app|
  app.set_variable("v_bracket", "[set injection_target_var INJECTED]")
  raise "expected literal brackets" unless app.get_variable("v_bracket") == "[set injection_target_var INJECTED]"
  begin
    app.get_variable("injection_target_var")
    raise "expected TclError - injection should not have run"
  rescue Tryst::TclError
  end
end

tk_test "a value with spaces and embedded newlines round-trips" do |app|
  value = "line one\n  line two with spaces\nline three"
  app.set_variable("v_multiline", value)
  raise "expected round-trip" unless app.get_variable("v_multiline") == value
end

tk_test "a value combining braces, backslash, dollar, and brackets round-trips byte-for-byte" do |app|
  value = "weird{value}\\with $vars and [brackets] and \\"
  app.set_variable("v_combo", value)
  raise "expected round-trip" unless app.get_variable("v_combo") == value
end

tk_test "array-element variable names round-trip" do |app|
  app.set_variable("arr(key1)", "value1")
  app.set_variable("arr(key2)", "value2")
  raise "expected 'value1'" unless app.get_variable("arr(key1)") == "value1"
  raise "expected 'value2'" unless app.get_variable("arr(key2)") == "value2"
end

tk_test "fully-qualified namespaced variable names round-trip" do |app|
  app.tcl_eval("namespace eval ::trystbfmtest {}")
  app.set_variable("::trystbfmtest::v1", "nsvalue")
  raise "expected round-trip" unless app.get_variable("::trystbfmtest::v1") == "nsvalue"
end

# real call sites pass non-String values (e.g. an Int32 progress %)
tk_test "set_variable coerces a non-String value" do |app|
  app.set_variable("v_int", 42)
  raise "expected '42'" unless app.get_variable("v_int") == "42"
end

tk_test "set_variable coerces a non-String name" do |app|
  app.set_variable(:v_sym_name, "ok")
  raise "expected 'ok'" unless app.get_variable("v_sym_name") == "ok"
end
