require "../tk_test_registry"

module Tryst
  class Interp
    # @api private - test-only forwarder, so the non-fast-path branch
    # can be exercised against a hand-built block (no real Tk photo
    # reports a non-packed-RGBA layout to test it through otherwise).
    def test_copy_pixels(block : LibTk::PhotoImageBlock, dest : Bytes,
                         x_off : Int32, y_off : Int32, width : Int32, height : Int32) : Nil
      copy_pixels(block, dest, x_off, y_off, width, height)
    end
  end
end

private def solid(r : Int32, g : Int32, b : Int32, a : Int32, pixels : Int32) : Bytes
  channels = StaticArray[r.to_u8, g.to_u8, b.to_u8, a.to_u8]
  Bytes.new(pixels * 4) { |i| channels[i % 4] }
end

private def assert_pixel(photo, x : Int32, y : Int32, expected : Tuple(Int32, Int32, Int32, Int32), label : String) : Nil
  actual = photo.get_pixel(x, y)
  got = {actual[:r], actual[:g], actual[:b], actual[:a]}
  raise "#{label}: expected #{expected} at (#{x},#{y}), got #{got}" unless got == expected
end

private def expect_argument_error(label : String, & : ->) : Nil
  yield
  raise "expected an ArgumentError for #{label}"
rescue ArgumentError
end

tk_test "Photo auto-generates unique names" do |app|
  first = Tryst::Photo.new(app, width: 1, height: 1)
  second = Tryst::Photo.new(app, width: 1, height: 1)

  raise "expected distinct names, both were #{first.name}" if first.name == second.name
  [first, second].each do |photo|
    raise "expected a tryst_photoN name, got #{photo.name.inspect}" unless photo.name.matches?(/\Atryst_photo\d+\z/)
  end
ensure
  first.try(&.delete)
  second.try(&.delete)
end

tk_test "Photo equality is by image name" do |app|
  first = Tryst::Photo.new(app, name: "eq_photo", width: 1, height: 1)
  same = Tryst::Photo.new(app, name: "eq_photo", width: 1, height: 1)
  other = Tryst::Photo.new(app, name: "eq_photo_other", width: 1, height: 1)

  raise "expected two handles on eq_photo to compare equal" unless first == same
  raise "expected different names to compare unequal" if first == other
  raise "expected matching hash" unless first.name.hash == first.hash
ensure
  first.try(&.delete)
  other.try(&.delete)
end

tk_test "Photo accepts an explicit name, and #to_s is that name" do |app|
  photo = Tryst::Photo.new(app, name: "my_test_photo", width: 10, height: 10)

  raise "expected my_test_photo, got #{photo.name.inspect}" unless photo.name == "my_test_photo"
  raise "expected #to_s to be the name, got #{photo}" unless photo.to_s == "my_test_photo"
ensure
  photo.try(&.delete)
end

# Photo#delete/#exists? go through tcl_invoke rather than string-
# interpolating @name into a tcl_eval script - a name containing a
# brace or semicolon could otherwise close the command early and run
# whatever followed as its own Tcl command. tcl_invoke keeps @name one
# argv element regardless of its content.
tk_test "Photo#delete and #exists? work for a name containing } and ;" do |app|
  photo = Tryst::Photo.new(app, name: "weird}photo;name", width: 2, height: 2)

  raise "expected the photo to exist" unless photo.exists?

  photo.delete
  raise "expected the photo to no longer exist after #delete" if photo.exists?
end

tk_test "Photo's constructor sets its dimensions" do |app|
  photo = Tryst::Photo.new(app, width: 42, height: 17)

  size = photo.get_size
  raise "expected 42x17, got #{size}" unless size == {width: 42, height: 17}
ensure
  photo.try(&.delete)
end

tk_test "Photo#exists? tracks creation and #delete" do |app|
  photo = Tryst::Photo.new(app, width: 5, height: 5)
  raise "expected the photo to exist after creation" unless photo.exists?

  photo.delete
  raise "expected the photo not to exist after delete" if photo.exists?
end

tk_test "Photo#inspect names the image" do |app|
  photo = Tryst::Photo.new(app, name: "inspect_test", width: 1, height: 1)

  raise "got #{photo.inspect}" unless photo.inspect == "#<Tryst::Photo inspect_test>"
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block writes pixels and #get_image reads them back" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)
  photo.put_block(solid(255, 0, 0, 255, 100), 10, 10)

  result = photo.get_image
  raise "expected 10x10, got #{result[:width]}x#{result[:height]}" unless result[:width] == 10 && result[:height] == 10
  raise "expected 400 bytes, got #{result[:data].size}" unless result[:data].size == 400

  data = result[:data]
  first = {data[0], data[1], data[2], data[3]}
  raise "first pixel: got #{first}" unless first == {255_u8, 0_u8, 0_u8, 255_u8}
  last = {data[396], data[397], data[398], data[399]}
  raise "last pixel: got #{last}" unless last == {255_u8, 0_u8, 0_u8, 255_u8}
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block with an x/y offset writes only to that region" do |app|
  photo = Tryst::Photo.new(app, width: 20, height: 20)
  photo.put_block(solid(0, 0, 0, 255, 400), 20, 20)
  photo.put_block(solid(0, 255, 0, 255, 25), 5, 5, x: 10, y: 10)

  assert_pixel(photo, 5, 5, {0, 0, 0, 255}, "well outside the block")
  assert_pixel(photo, 12, 12, {0, 255, 0, 255}, "inside the block")
  assert_pixel(photo, 10, 10, {0, 255, 0, 255}, "the block's own corner")
  assert_pixel(photo, 9, 10, {0, 0, 0, 255}, "one pixel left of the block")
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block returns self, for chaining" do |app|
  photo = Tryst::Photo.new(app, width: 2, height: 2)

  returned = photo.put_block(solid(255, 0, 0, 255, 4), 2, 2)
  raise "expected the same Photo back" unless returned.same?(photo)
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block rejects pixel data that isn't width*height*4 bytes" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)

  begin
    photo.put_block(Bytes.new(9), 10, 10)
    raise "expected ArgumentError for a short buffer"
  rescue ex : ArgumentError
    raise "expected a size-mismatch message, got #{ex.message.inspect}" unless ex.message.to_s.includes?("size mismatch")
  end
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block rejects a zero dimension" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)

  begin
    photo.put_block(Bytes.new(0), 0, 10)
    raise "expected ArgumentError for a zero width"
  rescue ex : ArgumentError
    raise "expected a 'positive' message, got #{ex.message.inspect}" unless ex.message.to_s.includes?("positive")
  end
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block preserves a transparent pixel's color channels" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)
  photo.put_block(solid(255, 0, 0, 0, 100), 10, 10)

  pixel = photo.get_pixel(5, 5)
  raise "expected alpha 0, got #{pixel[:a]}" unless pixel[:a].zero?
  raise "expected red preserved at 255, got #{pixel[:r]}" unless pixel[:r] == 255
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block format: :argb maps the channels correctly" do |app|
  photo = Tryst::Photo.new(app, width: 1, height: 1)

  # ARGB is 0xAARRGGBB little-endian, so the bytes run [B, G, R, A].
  # This is green: B=0, G=255, R=0, A=255.
  photo.put_block(Bytes[0, 255, 0, 255], 1, 1, format: :argb)

  assert_pixel(photo, 0, 0, {0, 255, 0, 255}, "argb green")
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block format: :argb reads a red pixel back as red" do |app|
  photo = Tryst::Photo.new(app, width: 1, height: 1)
  photo.put_block(Bytes[0, 0, 255, 255], 1, 1, format: :argb)

  assert_pixel(photo, 0, 0, {255, 0, 0, 255}, "argb red")
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block composite: :set overwrites what was there" do |app|
  photo = Tryst::Photo.new(app, width: 1, height: 1)
  photo.put_block(Bytes[255, 0, 0, 255], 1, 1)
  photo.put_block(Bytes[0, 0, 255, 255], 1, 1, composite: :set)

  assert_pixel(photo, 0, 0, {0, 0, 255, 255}, "composite set")
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block composite: :overlay alpha-blends over what was there" do |app|
  photo = Tryst::Photo.new(app, width: 1, height: 1)
  photo.put_block(Bytes[255, 0, 0, 255], 1, 1)
  photo.put_block(Bytes[0, 255, 0, 128], 1, 1, composite: :overlay)

  # Tk's exact blend arithmetic isn't the contract - that the two colors
  # mixed at all is.
  pixel = photo.get_pixel(0, 0)
  raise "expected red reduced by blending, got #{pixel[:r]}" unless pixel[:r] < 255
  raise "expected green present from the overlay, got #{pixel[:g]}" unless pixel[:g] > 0
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_zoomed_block replicates each source pixel zoom times" do |app|
  photo = Tryst::Photo.new(app, width: 30, height: 30)
  photo.put_zoomed_block(solid(255, 0, 0, 255, 100), 10, 10, zoom_x: 3, zoom_y: 3)

  { {0, 0}, {15, 15}, {29, 29} }.each do |(x, y)|
    assert_pixel(photo, x, y, {255, 0, 0, 255}, "3x zoom")
  end
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_zoomed_block handles an asymmetric zoom" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)
  photo.put_block(solid(0, 0, 0, 255, 100), 10, 10)
  photo.put_zoomed_block(Bytes[0, 0, 255, 255], 1, 1, zoom_x: 4, zoom_y: 2)

  # One source pixel zoomed 4x2 fills exactly (0,0)..(3,1).
  { {0, 0}, {3, 0}, {0, 1}, {3, 1} }.each do |(x, y)|
    assert_pixel(photo, x, y, {0, 0, 255, 255}, "inside the zoomed region")
  end
  assert_pixel(photo, 4, 0, {0, 0, 0, 255}, "one column past the zoomed region")
  assert_pixel(photo, 0, 2, {0, 0, 0, 255}, "one row below the zoomed region")
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_zoomed_block returns self" do |app|
  photo = Tryst::Photo.new(app, width: 4, height: 4)

  returned = photo.put_zoomed_block(Bytes[255, 0, 0, 255], 1, 1, zoom_x: 4, zoom_y: 4)
  raise "expected the same Photo back" unless returned.same?(photo)
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_zoomed_block rejects a non-positive zoom or subsample" do |app|
  photo = Tryst::Photo.new(app, width: 4, height: 4)

  begin
    photo.put_zoomed_block(Bytes[255, 0, 0, 255], 1, 1, zoom_x: 0)
    raise "expected ArgumentError for zoom_x: 0"
  rescue ex : ArgumentError
    raise "expected a zoom message, got #{ex.message.inspect}" unless ex.message.to_s.includes?("zoom")
  end

  begin
    photo.put_zoomed_block(Bytes[255, 0, 0, 255], 1, 1, subsample_y: 0)
    raise "expected ArgumentError for subsample_y: 0"
  rescue ex : ArgumentError
    raise "expected a subsample message, got #{ex.message.inspect}" unless ex.message.to_s.includes?("subsample")
  end
ensure
  photo.try(&.delete)
end

tk_test "Photo#get_image reads back a sub-region" do |app|
  photo = Tryst::Photo.new(app, width: 20, height: 20)
  photo.put_block(solid(0, 0, 0, 255, 400), 20, 20)
  photo.put_block(solid(0, 255, 0, 255, 100), 10, 10, x: 10, y: 10)

  green = photo.get_image(x: 10, y: 10, width: 10, height: 10)
  raise "expected a 10x10 region, got #{green[:width]}x#{green[:height]}" unless green[:width] == 10 && green[:height] == 10
  first = {green[:data][0], green[:data][1], green[:data][2], green[:data][3]}
  raise "green quadrant: got #{first}" unless first == {0_u8, 255_u8, 0_u8, 255_u8}

  black = photo.get_image(x: 0, y: 0, width: 10, height: 10)
  first = {black[:data][0], black[:data][1], black[:data][2], black[:data][3]}
  raise "black quadrant: got #{first}" unless first == {0_u8, 0_u8, 0_u8, 255_u8}
ensure
  photo.try(&.delete)
end

tk_test "Photo#get_image clamps a region that runs past the image edge" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)
  photo.put_block(solid(0, 0, 0, 255, 100), 10, 10)

  result = photo.get_image(x: 6, y: 6, width: 99, height: 99)
  raise "expected the region clamped to 4x4, got #{result[:width]}x#{result[:height]}" unless result[:width] == 4 && result[:height] == 4
  raise "expected 64 bytes, got #{result[:data].size}" unless result[:data].size == 64
ensure
  photo.try(&.delete)
end

tk_test "Photo#get_image rejects an offset outside the image" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)
  photo.put_block(solid(0, 0, 0, 255, 100), 10, 10)

  begin
    photo.get_image(x: 10, y: 0)
    raise "expected ArgumentError for an offset at the edge"
  rescue ex : ArgumentError
    raise "expected an out-of-bounds message, got #{ex.message.inspect}" unless ex.message.to_s.includes?("outside image bounds")
  end
ensure
  photo.try(&.delete)
end

tk_test "copy_pixels reads a non-packed-RGBA layout correctly (BGRA, via a hand-built block)" do |app|
  src = Bytes[2, 1, 0, 255, 20, 10, 0, 200] # two BGRA pixels
  block = LibTk::PhotoImageBlock.new
  block.pixel_ptr = src.to_unsafe
  block.width = 2
  block.height = 1
  block.pitch = 8
  block.pixel_size = 4
  block.offset = StaticArray[2, 1, 0, 3]

  dest = Bytes.new(8)
  app.interp.test_copy_pixels(block, dest, 0, 0, 2, 1)

  expected = Bytes[0, 1, 2, 255, 0, 10, 20, 200]
  raise "expected #{expected.to_a}, got #{dest.to_a}" unless dest == expected
end

tk_test "copy_pixels fills opaque alpha for a source with no alpha channel" do |app|
  src = Bytes[10, 20, 30, 40, 50, 60] # two RGB (pixel_size 3) pixels, no alpha
  block = LibTk::PhotoImageBlock.new
  block.pixel_ptr = src.to_unsafe
  block.width = 2
  block.height = 1
  block.pitch = 6
  block.pixel_size = 3
  block.offset = StaticArray[0, 1, 2, 3]

  dest = Bytes.new(8)
  app.interp.test_copy_pixels(block, dest, 0, 0, 2, 1)

  expected = Bytes[10, 20, 30, 255, 40, 50, 60, 255]
  raise "expected #{expected.to_a}, got #{dest.to_a}" unless dest == expected
end

tk_test "Photo#get_pixel reads exact RGBA values, including partial alpha" do |app|
  photo = Tryst::Photo.new(app, width: 3, height: 1)
  photo.put_block(Bytes[255, 0, 0, 255, 0, 255, 0, 200, 0, 0, 255, 128], 3, 1)

  assert_pixel(photo, 0, 0, {255, 0, 0, 255}, "opaque red")
  assert_pixel(photo, 1, 0, {0, 255, 0, 200}, "green at alpha 200")
  assert_pixel(photo, 2, 0, {0, 0, 255, 128}, "blue at alpha 128")
ensure
  photo.try(&.delete)
end

tk_test "Photo#get_pixel rejects out-of-bounds coordinates" do |app|
  photo = Tryst::Photo.new(app, width: 5, height: 5)
  photo.put_block(solid(0, 0, 0, 255, 25), 5, 5)

  { {5, 0}, {0, 5} }.each do |(x, y)|
    photo.get_pixel(x, y)
    raise "expected ArgumentError for (#{x},#{y})"
  rescue ex : ArgumentError
    raise "expected an out-of-bounds message, got #{ex.message.inspect}" unless ex.message.to_s.includes?("outside image bounds")
  end
ensure
  photo.try(&.delete)
end

tk_test "Photo#get_size reports the dimensions it was built with" do |app|
  { {10, 10}, {100, 50}, {1, 200} }.each do |(width, height)|
    photo = Tryst::Photo.new(app, width: width, height: height)
    begin
      size = photo.get_size
      raise "expected #{width}x#{height}, got #{size}" unless size == {width: width, height: height}
    ensure
      photo.delete
    end
  end
end

tk_test "Photo#set_size grows and shrinks the image, and returns self" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)

  returned = photo.set_size(20, 30)
  raise "expected the same Photo back" unless returned.same?(photo)
  raise "expected 20x30, got #{photo.get_size}" unless photo.get_size == {width: 20, height: 30}

  photo.set_size(5, 5)
  raise "expected 5x5, got #{photo.get_size}" unless photo.get_size == {width: 5, height: 5}
ensure
  photo.try(&.delete)
end

tk_test "Photo#expand grows an auto-sized photo without disturbing its pixels" do |app|
  # No width:/height: - expand is a no-op on a photo given an explicit
  # size, so the size has to come from the pixels written below.
  photo = Tryst::Photo.new(app)
  photo.put_block(solid(255, 0, 0, 255, 100), 10, 10)
  raise "expected 10x10 after put_block, got #{photo.get_size}" unless photo.get_size == {width: 10, height: 10}

  returned = photo.expand(20, 30)
  raise "expected the same Photo back" unless returned.same?(photo)

  size = photo.get_size
  raise "expected width >= 20, got #{size[:width]}" unless size[:width] >= 20
  raise "expected height >= 30, got #{size[:height]}" unless size[:height] >= 30
  assert_pixel(photo, 5, 5, {255, 0, 0, 255}, "an original pixel after expand")
ensure
  photo.try(&.delete)
end

tk_test "Photo#expand never shrinks" do |app|
  photo = Tryst::Photo.new(app)
  photo.put_block(solid(0, 0, 0, 255, 400), 20, 20)

  photo.expand(5, 5)

  size = photo.get_size
  raise "expected it to stay at least 20x20, got #{size}" unless size[:width] >= 20 && size[:height] >= 20
ensure
  photo.try(&.delete)
end

tk_test "Photo#expand is a no-op on a photo created with explicit width/height" do |app|
  # Tk's own documented behavior - expand does nothing once a definite
  # size has been declared.
  photo = Tryst::Photo.new(app, width: 10, height: 10)

  photo.expand(20, 20)

  raise "expected it to stay 10x10, got #{photo.get_size}" unless photo.get_size == {width: 10, height: 10}
ensure
  photo.try(&.delete)
end

tk_test "Photo#blank clears every pixel to fully transparent, and returns self" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)
  photo.put_block(solid(255, 0, 0, 255, 100), 10, 10)
  assert_pixel(photo, 5, 5, {255, 0, 0, 255}, "before blank")

  returned = photo.blank
  raise "expected the same Photo back" unless returned.same?(photo)

  assert_pixel(photo, 5, 5, {0, 0, 0, 0}, "after blank")
ensure
  photo.try(&.delete)
end

tk_test "Photo#clear is #blank" do |app|
  photo = Tryst::Photo.new(app, width: 5, height: 5)
  photo.put_block(solid(255, 0, 0, 255, 25), 5, 5)

  photo.clear

  assert_pixel(photo, 2, 2, {0, 0, 0, 0}, "after clear")
ensure
  photo.try(&.delete)
end

tk_test "Photo round-trips a multi-color pattern across both rows" do |app|
  photo = Tryst::Photo.new(app, width: 3, height: 2)
  photo.put_block(Bytes[
    255, 0, 0, 255,     # red
    0, 255, 0, 255,     # green
    0, 0, 255, 255,     # blue
    255, 255, 255, 255, # white
    0, 0, 0, 255,       # black
    255, 255, 0, 255,   # yellow
  ], 3, 2)

  assert_pixel(photo, 0, 0, {255, 0, 0, 255}, "red")
  assert_pixel(photo, 1, 0, {0, 255, 0, 255}, "green")
  assert_pixel(photo, 2, 0, {0, 0, 255, 255}, "blue")
  assert_pixel(photo, 0, 1, {255, 255, 255, 255}, "white")
  assert_pixel(photo, 1, 1, {0, 0, 0, 255}, "black")
  assert_pixel(photo, 2, 1, {255, 255, 0, 255}, "yellow")
ensure
  photo.try(&.delete)
end

tk_test "Photo#command passes arbitrary photo subcommands through, e.g. copy -subsample" do |app|
  source = Tryst::Photo.new(app, width: 40, height: 20)
  source.put_block(solid(255, 0, 0, 255, 800), 40, 20)
  dest = Tryst::Photo.new(app, name: "tryst_test_copy_dest")

  dest.command(:copy, source.name, subsample: 4)

  raise "expected the copy to be 10x5, got #{dest.get_size}" unless dest.get_size == {width: 10, height: 5}
ensure
  source.try(&.delete)
  dest.try(&.delete)
end

tk_test "Photo.finalizer_for's proc deletes the image it names" do |app|
  app.command(:image, :create, :photo, "tryst_test_finalizer_target", width: 5, height: 5)
  raise "expected the image to exist first" unless app.split_list(app.tcl_eval("image names")).includes?("tryst_test_finalizer_target")

  Tryst::Photo.finalizer_for("tryst_test_finalizer_target", app).call
  # pump_once, not app.update: the finalizer only QUEUES the delete via
  # Interp#queue_for_main (a finalizer can run on any thread). app.update
  # runs Tcl's own event loop, which knows nothing about that Crystal-side
  # queue - pump_once is what drains it.
  app.interp.pump_once

  names = app.split_list(app.tcl_eval("image names"))
  raise "expected the finalizer proc to have deleted the image" if names.includes?("tryst_test_finalizer_target")
end

# .delete_task (what .finalizer_for wraps) builds its `catch` script
# with Tryst.make_list rather than tcl_eval interpolation - a plain
# "catch {image delete #{name}}" string doesn't round-trip a name
# containing a brace.
tk_test "Photo.finalizer_for's proc deletes the image even when its name contains } and ;" do |app|
  hazard_name = "weird}photo;target"
  app.command(:image, :create, :photo, hazard_name, width: 5, height: 5)
  raise "expected the image to exist first" unless app.split_list(app.tcl_eval("image names")).includes?(hazard_name)

  Tryst::Photo.finalizer_for(hazard_name, app).call
  app.interp.pump_once

  names = app.split_list(app.tcl_eval("image names"))
  raise "expected the finalizer proc to have deleted the image" if names.includes?(hazard_name)
end

tk_test "an explicitly deleted Photo's finalizer can't delete a later same-named image" do |app|
  photo = Tryst::Photo.new(app, width: 5, height: 5)
  name = photo.name
  photo.delete

  # Recreate at the same name, then run the first Photo's finalizer by
  # hand - what a later GC would do. Crystal has no way to unregister a
  # finalizer, so #delete sets a guard flag instead, and this is the
  # observable contract that flag exists to keep.
  replacement = Tryst::Photo.new(app, name: name, width: 5, height: 5)
  photo.finalize
  # Has to be pump_once for the same reason as the case above - with a
  # plain app.update nothing drains the queue, so this would pass whether
  # the guard flag worked or not.
  app.interp.pump_once

  raise "a stale finalizer must not delete a same-named image created after an explicit delete" unless replacement.exists?
ensure
  replacement.try(&.delete)
end

tk_test "finalizing more Photos than @main_queue's capacity in one collection doesn't hang" do |app|
  # @main_queue (Interp#queue_for_main's backing Channel) has capacity
  # 64 - well below the 200 finalized here in one go, with nothing
  # draining it in between. A finalizer that queued through
  # #queue_for_main itself would suspend its fiber forever past the
  # 64th. Discard every Photo reference immediately so each one is only
  # reachable via GC.collect's finalization pass, not from this method's
  # own locals.
  200.times do
    Tryst::Photo.new(app, width: 2, height: 2)
  end

  # Boehm's conservative stack scanning means one GC.collect isn't
  # guaranteed to reclaim everything already unreachable - stale pointer
  # bit patterns can linger in unswept stack slots/registers from
  # earlier iterations and keep an object looking reachable for a cycle
  # or two longer. Retrying is the existing pattern for this in a
  # long-lived worker process (see .finalizer_for's doc comment); the
  # property under test is that this converges at all without hanging or
  # crashing, not that a single collect is exhaustive.
  remaining = [] of String
  10.times do
    GC.collect
    app.interp.pump_once
    remaining = app.split_list(app.tcl_eval("image names")).select(&.starts_with?("tryst_photo"))
    break if remaining.empty?
  end

  raise "expected no tryst_photo images to remain, still have #{remaining}" unless remaining.empty?
end

tk_test "Photo.new(file:) loads an image, and copy -subsample halves it" do |app|
  path = File.tempname("tryst_photo_spec", ".png")

  seed = Tryst::Photo.new(app, width: 80, height: 40)
  seed.put_block(solid(0, 0, 255, 255, 3200), 80, 40)
  seed.command(:write, path, format: "png")
  seed.delete

  loaded = Tryst::Photo.new(app, file: path)
  raise "expected the loaded image to be 80x40, got #{loaded.get_size}" unless loaded.get_size == {width: 80, height: 40}

  small = Tryst::Photo.new(app)
  small.command(:copy, loaded.name, subsample: 2)
  raise "expected the subsampled copy to be 40x20, got #{small.get_size}" unless small.get_size == {width: 40, height: 20}
ensure
  loaded.try(&.delete)
  small.try(&.delete)
  File.delete?(path) if path
end

# -- Photo.from_svg --
#
# No COMPILE-TIME TCL_VERSION branch here on purpose - #from_svg itself
# has none (see its own doc comment on why: -format svg is a plain
# Tcl-level command, not a raw C symbol, so its behavior is a property
# of whatever Tk is ACTUALLY loaded at runtime). It DOES have a real
# RUNTIME gate though - app.tcl_major_version, checked proactively
# before ever touching Tcl, not inferred from whatever error Tcl itself
# would raise. These cases run on both the 8.6 and 9.x suites and
# assert accordingly, branching on that same real runtime-detected
# version (never Tryst::TCL_MAJOR_VERSION, which is compile-time only)
# - the distinction the method's own doc comment draws.
private def tiny_svg
  %(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="red"/></svg>)
end

tk_test "Photo.from_svg loads real content on Tk 9.x, and raises a clear version error on 8.6 - checked proactively via app.tcl_major_version, not inferred from Tcl's own error" do |app|
  path = File.tempname("tryst_photo_svg_spec", ".svg")
  File.write(path, tiny_svg)

  if app.tcl_major_version >= 9
    photo = Tryst::Photo.from_svg(app, path: path)
    raise "expected 10x10, got #{photo.get_size}" unless photo.get_size == {width: 10, height: 10}
    photo.delete
  else
    begin
      Tryst::Photo.from_svg(app, path: path)
      raise "expected a TclError under Tk #{app.tcl_patch_level}"
    rescue ex : Tryst::TclError
      unless ex.message.try(&.includes?("9.x"))
        raise "expected the error to name the version requirement, got #{ex.message.inspect}"
      end
    end
  end
ensure
  File.delete?(path) if path
end

tk_test "Photo.from_svg needs exactly one of path: or data:" do |app|
  path = File.tempname("tryst_photo_svg_spec", ".svg")
  File.write(path, tiny_svg)

  expect_argument_error("neither path: nor data:") { Tryst::Photo.from_svg(app) }
  expect_argument_error("both path: and data:") { Tryst::Photo.from_svg(app, path: path, data: tiny_svg) }
ensure
  File.delete?(path) if path
end

tk_test "Photo.from_svg rejects combining any two of scale:/scaletowidth:/scaletoheight:" do |app|
  path = File.tempname("tryst_photo_svg_spec", ".svg")
  File.write(path, tiny_svg)

  expect_argument_error("scale: + scaletowidth:") { Tryst::Photo.from_svg(app, path: path, scale: 2.0, scaletowidth: 40) }
  expect_argument_error("scaletowidth: + scaletoheight:") do
    Tryst::Photo.from_svg(app, path: path, scaletowidth: 40, scaletoheight: 40)
  end
ensure
  File.delete?(path) if path
end

tk_test "Photo.from_svg's dpi:/scale:/scaletowidth:/scaletoheight: actually take effect (Tk 9.x only)" do |app|
  next unless app.tcl_major_version >= 9

  path = File.tempname("tryst_photo_svg_spec", ".svg")
  File.write(path, tiny_svg)

  by_scale = Tryst::Photo.from_svg(app, path: path, scale: 3.0)
  raise "expected 30x30 at scale: 3.0, got #{by_scale.get_size}" unless by_scale.get_size == {width: 30, height: 30}

  by_width = Tryst::Photo.from_svg(app, path: path, scaletowidth: 40)
  raise "expected 40x40 (aspect-preserving) at scaletowidth: 40, got #{by_width.get_size}" unless by_width.get_size == {width: 40, height: 40}

  # dpi: alone doesn't change reported size for an SVG using unitless
  # dimensions (this fixture's own width/height attrs) - it only affects
  # physical-unit (mm/pt/in) content, which this fixture has none of.
  # Combines cleanly with scaletowidth: though, unlike the scale trio.
  combined = Tryst::Photo.from_svg(app, path: path, dpi: 192, scaletowidth: 40)
  raise "expected 40x40, got #{combined.get_size}" unless combined.get_size == {width: 40, height: 40}

  by_scale.delete
  by_width.delete
  combined.delete
ensure
  File.delete?(path) if path
end

tk_test "Photo.from_svg's data: is raw SVG text, not base64 (Tk 9.x only)" do |app|
  next unless app.tcl_major_version >= 9

  photo = Tryst::Photo.from_svg(app, data: tiny_svg)
  raise "expected 10x10, got #{photo.get_size}" unless photo.get_size == {width: 10, height: 10}
  photo.delete
end
