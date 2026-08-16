require "../../src/tryst/ui"

# Standalone verification for Handle's canvas shape-creation methods and
# CanvasItem's real Tk behavior - needs its own subprocess for the same
# reason grid_fixture.cr/overlay_fixture.cr do (Session#realize always
# constructs a brand-new Tryst::App). The exact Tcl commands each method
# builds are already covered headlessly against FakeApp (spec/tryst/ui/
# handle_spec.cr, spec/tryst/ui/canvas_item_spec.cr); this confirms Tk's
# own canvas actually behaves as expected - matching ruby-tryst's
# tryst-ui/test/test_canvas_items.rb, minus its on_drag/#draggable cases
# (deferred - see canvas_item.cr's own doc comment) and its menu-based
# on_right_click case (needs a real context_menu widget type, not ported
# yet - covered headlessly instead, via a bare :context_menu Node/Handle).

session = Tryst::UI.app(title: "canvas items fixture") { |builder| builder.canvas(:board, width: 200, height: 200) }
app = session.realize
app.show
app.update

board = session[:board]

# Case 1: #line creates a real line item; #coords reads it back.
item = board.line(10, 10, 50, 50, fill: "red")
item_type = app.tcl_eval("#{board.path} type #{item.tag_or_id}")
raise "expected a line item, got #{item_type}" unless item_type == "line"
raise "expected coords [10.0, 10.0, 50.0, 50.0], got #{item.coords}" unless item.coords == [10.0, 10.0, 50.0, 50.0]

# Case 2: every shape method creates the matching Tk item type.
{
  "oval"      => board.oval(10, 10, 40, 40),
  "rectangle" => board.rectangle(10, 10, 40, 40),
  "polygon"   => board.polygon(10, 10, 40, 10, 25, 40),
  "text"      => board.text(10, 10, text: "Hi"),
  "arc"       => board.arc(10, 10, 40, 40, start: 0, extent: 90),
  "bitmap"    => board.bitmap(10, 10, bitmap: "gray25"),
}.each do |expected_type, shape_item|
  actual_type = app.tcl_eval("#{board.path} type #{shape_item.tag_or_id}")
  raise "expected a #{expected_type} item, got #{actual_type}" unless actual_type == expected_type
end

# Case 2b: #image, kept out of the table above because it needs a real
# Tk image to point at rather than a self-contained option value.
photo = Tryst::Photo.new(app, width: 8, height: 8)
photo_item = board.image(0, 0, image: photo.name, anchor: :nw)
photo_item_type = app.tcl_eval("#{board.path} type #{photo_item.tag_or_id}")
raise "expected an image item, got #{photo_item_type}" unless photo_item_type == "image"
unless photo_item[:image] == photo.name
  raise "expected the item to reference #{photo.name}, got #{photo_item[:image]}"
end
# The bounding box comes from the photo's own dimensions, so this is what
# proves Tk actually resolved the name to that image rather than just
# storing the string - an unresolvable one errors at create time.
unless photo_item.bounds == [0.0, 0.0, 8.0, 8.0]
  raise "expected the image item to be 8x8 at the origin, got #{photo_item.bounds}"
end

# Case 3: flat and nested coordinate arguments produce the same item.
flat = board.line(10, 10, 50, 50)
nested = board.line([10, 10], [50, 50])
raise "expected flat/nested coords to match, got #{flat.coords} vs #{nested.coords}" unless flat.coords == nested.coords

# Case 4: #move shifts by a relative delta.
move_item = board.oval(10, 10, 30, 30)
move_item.move(5, -3)
raise "expected [15.0, 7.0, 35.0, 27.0] after move, got #{move_item.coords}" unless move_item.coords == [15.0, 7.0, 35.0, 27.0]

# Case 5: #coords= replaces the coordinate list outright, not a shift.
coords_item = board.line(0, 0, 10, 10)
coords_item.coords = [1, 2, 3, 4, 5, 6]
expected_coords = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
raise "expected #{expected_coords} after coords=, got #{coords_item.coords}" unless coords_item.coords == expected_coords

# Case 6: #configure mutates options; #[] reads them back.
configure_item = board.rectangle(10, 10, 40, 40, fill: "blue")
configure_item.configure(fill: "green", width: 3)
raise "expected fill green, got #{configure_item[:fill]}" unless configure_item[:fill] == "green"
raise "expected width 3.0, got #{configure_item[:width]}" unless configure_item[:width] == "3.0"

# Case 7: #[]= writes a single option.
bracket_item = board.oval(10, 10, 40, 40, fill: "red")
raise "expected fill red, got #{bracket_item[:fill]}" unless bracket_item[:fill] == "red"
bracket_item[:fill] = "purple"
raise "expected fill purple after []=, got #{bracket_item[:fill]}" unless bracket_item[:fill] == "purple"

# Case 8: #delete removes the item; #exists?/#bounds reflect that.
delete_item = board.oval(10, 10, 40, 40)
raise "expected the item to exist before delete" unless delete_item.exists?
delete_item.delete
raise "expected the item to not exist after delete" if delete_item.exists?
raise "expected bounds to be nil after delete" unless delete_item.bounds.nil?

# Case 9: bring_to_front/send_to_back with no target move all the way.
# find all reports the WHOLE canvas's stacking order (every item created
# in every earlier case above too), so this filters down to just a/b/c's
# own ids - their relative order survives filtering unchanged.
a = board.oval(10, 10, 20, 20)
b = board.oval(10, 10, 20, 20)
c = board.oval(10, 10, 20, 20)
abc_ids = [a.tag_or_id, b.tag_or_id, c.tag_or_id]
stacking = -> { app.split_list(app.tcl_eval("#{board.path} find all")).select { |id| abc_ids.includes?(id) } }

initial_stack = stacking.call
raise "expected a, b, c in that order, got #{initial_stack}" unless initial_stack == [a.tag_or_id, b.tag_or_id, c.tag_or_id]

a.bring_to_front
after_front = stacking.call
raise "expected b, c, a after bring_to_front, got #{after_front}" unless after_front == [b.tag_or_id, c.tag_or_id, a.tag_or_id]

c.send_to_back
after_back = stacking.call
raise "expected c, b, a after send_to_back, got #{after_back}" unless after_back == [c.tag_or_id, b.tag_or_id, a.tag_or_id]

# Case 10: bring_to_front(target) repositions just above target, not to the very top.
d = board.oval(10, 10, 20, 20)
e = board.oval(10, 10, 20, 20)
board.oval(10, 10, 20, 20)
d.bring_to_front(e)
target_stack = app.split_list(app.tcl_eval("#{board.path} find all"))
d_index = target_stack.index!(d.tag_or_id)
e_index = target_stack.index!(e.tag_or_id)
raise "expected d to land directly after e, got #{target_stack}" unless d_index == e_index + 1

# Case 11: #scale resizes relative to a given origin.
scale_item = board.rectangle(10, 10, 20, 20)
scale_item.scale(10, 10, 2, 2)
expected_scaled = [10.0, 10.0, 30.0, 30.0]
raise "expected #{expected_scaled} after scale, got #{scale_item.coords}" unless scale_item.coords == expected_scaled

# Case 12: #bounds returns the item's bounding box.
bounds_item = board.rectangle(10, 10, 40, 40, outline: "", fill: "red")
box = bounds_item.bounds
raise "expected a 4-element bounding box, got #{box.inspect}" unless box && box.size == 4

# Case 13: #tagged addresses a shared tag as one movable/configurable/deletable group.
one = board.oval(10, 10, 20, 20, tags: "group_a")
two = board.oval(30, 30, 40, 40, tags: "group_a")
board.oval(50, 50, 60, 60, tags: "group_b")

group = board.tagged("group_a")
raise "expected group_a to exist" unless group.exists?

group.move(5, 5)
raise "expected one to have moved with the group, got #{one.coords}" unless one.coords == [15.0, 15.0, 25.0, 25.0]
raise "expected two to have moved with the group, got #{two.coords}" unless two.coords == [35.0, 35.0, 45.0, 45.0]

group.configure(fill: "orange")
raise "expected one's fill to follow the group configure" unless one[:fill] == "orange"
raise "expected two's fill to follow the group configure" unless two[:fill] == "orange"

group.delete
raise "expected one to be gone after group delete" if one.exists?
raise "expected two to be gone after group delete" if two.exists?
raise "expected group_b to be untouched" unless board.tagged("group_b").exists?

# Case 14: #tagged on an unused tag reports exists? false, not raise.
raise "expected an unused tag to report exists? false" if board.tagged("nothing_has_this_tag").exists?

# Case 15: on_click's bound script is scoped per-item, not shared - item-
# level canvas bindings only fire through Tk's "current item" tracking
# (real event generate positioning depends on real X11 pointer state,
# unreliable under Xvfb), so this reads the bound script back and evals
# it directly instead of simulating a real click.
click_a = board.oval(10, 10, 30, 30)
click_b = board.oval(100, 100, 120, 120)
a_hits = 0
b_hits = 0
click_a.on_click { |_args, _signal| a_hits += 1 }
click_b.on_click { |_args, _signal| b_hits += 1 }

a_script = app.tcl_eval("#{board.path} bind #{click_a.tag_or_id} <Button-1>")
app.tcl_eval(a_script)
raise "expected invoking A's binding to fire A's handler once, got #{a_hits}" unless a_hits == 1
raise "expected invoking A's binding to leave B untouched, got #{b_hits}" unless b_hits == 0

b_script = app.tcl_eval("#{board.path} bind #{click_b.tag_or_id} <Button-1>")
app.tcl_eval(b_script)
raise "expected invoking B's binding to leave A untouched, got #{a_hits}" unless a_hits == 1
raise "expected invoking B's binding to fire B's handler once, got #{b_hits}" unless b_hits == 1

# Case 16: on_right_click (block form) binds a script that fires the block.
right_click_item = board.oval(10, 10, 30, 30)
right_click_fired = false
right_click_item.on_right_click { |_args, _signal| right_click_fired = true }
right_click_script = app.tcl_eval("#{board.path} bind #{right_click_item.tag_or_id} <Button-3>")
app.tcl_eval(right_click_script)
raise "expected on_right_click's bound script to fire the given block" unless right_click_fired

# Case 17: deleting an item releases its on_click callback - not a leak.
baseline = app.interp.callback_ids.size
leak_item = board.oval(10, 10, 30, 30)
leak_item.on_click { |_args, _signal| }
after_bind = app.interp.callback_ids.size
raise "expected on_click to register exactly one callback, got #{after_bind - baseline}" unless after_bind == baseline + 1

leak_item.delete
after_delete = app.interp.callback_ids.size
raise "expected deleting the item to release its on_click callback, got #{after_delete} (baseline #{baseline})" unless after_delete == baseline

# Case 18: a canvas tag with Tcl-special characters is bound safely - not
# interpolated into a script the way CanvasBindInterceptor's post-bind
# requery once did (`#{path} bind #{tag_or_id} #{seq}`), which let a tag
# like this one perform Tcl command substitution as a side effect.
app.tcl_eval(%(set ::injection_probe none))
injection_tag = %(evil tag [set ::injection_probe hit] ${bad} } ; set ::injection_probe hit)
injection_hits = 0
injection_baseline = app.interp.callback_ids.size

injection_item = board.oval(10, 10, 30, 30, tags: injection_tag)
board.tagged(injection_tag).on_click { |_args, _signal| injection_hits += 1 }

unless app.interp.callback_ids.size == injection_baseline + 1
  raise "expected exactly one new callback to be tracked for the injected tag, got #{app.interp.callback_ids.size - injection_baseline}"
end
raise "expected the injected tag fragment to not run" unless app.tcl_eval("set ::injection_probe") == "none"

injection_script = app.tcl_invoke(board.path, "bind", injection_tag, "<Button-1>")
app.tcl_eval(injection_script)
raise "expected the binding to fire despite the tag's special characters" unless injection_hits == 1
raise "expected the injected tag fragment to still not run after the binding fired" unless app.tcl_eval("set ::injection_probe") == "none"

injection_item.delete

app.destroy
puts "OK"
