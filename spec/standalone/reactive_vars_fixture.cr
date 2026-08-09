require "../../src/teek/ui"

# Standalone verification for Var's real Tk behavior - needs its own
# subprocess for the same reason grid_fixture.cr/overlay_fixture.cr do
# (Session#realize always constructs a brand-new Teek::App). Var's
# pre-realize surface is already covered headlessly (spec/teek/ui/
# var_spec.cr); this confirms the real Tcl variable/trace/bind: wiring
# actually works - a Var and its bound widgets staying in sync in both
# directions, on_change firing with a coerced value, and Boolean's 1/0
# convention - matching ruby-teek's teek-ui/test/test_reactive_vars.rb.

handles = {} of Symbol => Teek::UI::Handle
vars = {} of Symbol => Teek::UI::Var
changes = [] of Teek::UI::VarValue

session = Teek::UI.app(title: "reactive vars fixture") do |builder|
  vars[:speed] = builder.var(5)
  vars[:speed].on_change { |value| changes << value }
  handles[:speed_slider] = builder.slider(:speed_slider, from: 1, to: 10, bind: vars[:speed])
  handles[:speed_label] = builder.label(:speed_label, bind: vars[:speed])

  vars[:name] = builder.var("")
  handles[:name_box] = builder.text_box(:name_box, bind: vars[:name])

  vars[:enabled] = builder.var(true)
  handles[:enabled_box] = builder.checkbox(:enabled_box, bind: vars[:enabled])
end

app = session.realize
app.show
app.update

speed = vars[:speed]
name_var = vars[:name]
enabled = vars[:enabled]
slider_path = handles[:speed_slider].path
label_path = handles[:speed_label].path
name_box_path = handles[:name_box].path

raise "expected speed.value to start at 5, got #{speed.value}" unless speed.value == 5

# slider -> var -> label
app.command(slider_path, :set, 7)
app.update
raise "expected speed.value to follow the slider, got #{speed.value}" unless speed.value == 7
# ttk::scale always stores/formats its bound variable as a float (e.g.
# "7.0"), even for a whole-number -from/-to range - compare numerically
# rather than assuming a particular string format.
label_text = app.command(label_path, :cget, "-text").to_f
raise "expected the label to follow the slider via the shared var, got #{label_text}" unless label_text == 7.0

# var -> slider and label
speed.value = 3
app.update
slider_value = app.command(slider_path, :get).to_f
raise "expected the slider to follow speed.value=, got #{slider_value}" unless slider_value == 3.0
label_text = app.command(label_path, :cget, "-text").to_f
raise "expected the label to follow speed.value=, got #{label_text}" unless label_text == 3.0

# on_change fires with a coerced Integer, triggered by the bound widget
app.command(slider_path, :set, 9)
app.update
raise "expected on_change to have fired with 9, got #{changes}" unless changes.includes?(9)
raise "expected on_change's value to be coerced to Int32, got #{changes.last.class}" unless changes.last.is_a?(Int32)

# var <-> text_box, in both directions
name_var.value = "hello"
app.update
box_text = app.command(name_box_path, :get)
raise "expected the text_box to follow name_var.value=, got #{box_text}" unless box_text == "hello"

app.command(name_box_path, :delete, 0, :end)
app.command(name_box_path, :insert, 0, "typed")
app.update
raise "expected name_var to follow what was typed, got #{name_var.value}" unless name_var.value == "typed"

# a Boolean var bound to a checkbox uses Tk's 1/0 convention and coerces back to true/false
raise "expected enabled.value to start true, got #{enabled.value}" unless enabled.value == true
raise "expected the backing Tcl variable to be \"1\", got #{app.get_variable(enabled.name)}" unless app.get_variable(enabled.name) == "1"

enabled.value = false
app.update
raise "expected enabled.value to become false, got #{enabled.value}" unless enabled.value == false
raise "expected the backing Tcl variable to be \"0\", got #{app.get_variable(enabled.name)}" unless app.get_variable(enabled.name) == "0"

app.destroy
puts "OK"
