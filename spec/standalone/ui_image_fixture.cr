require "base64"
require "../../src/teek/ui"

# Standalone verification for Teek::UI::Image against real Tk - the
# build-time name allocation, the load at realize, and the same
# declared-inside-#add and rolled-back-#add paths Var already gets.
#
# Needs its own subprocess (see spec/teek/ui/session_realtk_spec.cr):
# Session#realize always constructs a brand-new Teek::App. Image's
# pre-realize surface is headless instead, in spec/teek/ui/image_spec.cr.

# A 1x1 transparent GIF, so there is a real file for Tk to read. Decoded
# in Crystal rather than written out by Tk, because Session#realize
# constructs the only Teek::App this process is ever allowed (Tk_Init is
# one-shot per process) - there is no interpreter to write one with until
# after the very realize under test here.
GIF_1X1 = "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"

image_path = File.join(Dir.tempdir, "teek_ui_image_fixture.gif")
File.write(image_path, Base64.decode(GIF_1X1))

begin
  declared = nil.as(Teek::UI::Image?)

  session = Teek::UI.app(title: "ui image fixture") do |builder|
    declared = builder.image(image_path)
    builder.column(:list, &.label(:heading, text: "Items"))
    builder.grid(:form) do |grid|
      grid.cell(row: 0, col: 0) { grid.label(:name_label, text: "Name:") }
    end
  end

  image = declared.as(Teek::UI::Image)

  # Case 1: the name is allocated during build, with no interpreter and
  # no file read yet - #photo has nothing to hand back until realize.
  raise "image: expected teek_ui_image_1, got #{image.name}" unless image.name == "teek_ui_image_1"
  begin
    image.photo
    raise "image: expected NotRealizedError before realize"
  rescue Teek::UI::NotRealizedError
  end

  app = session.realize
  app.show
  app.update

  # Case 2: realize loaded the file into a real, correctly named photo.
  photo = image.photo
  raise "image: expected the photo to carry the declared name, got #{photo.name}" unless photo.name == image.name
  size = photo.get_size
  raise "image: expected a 1x1 photo, got #{size}" unless size == {width: 1, height: 1}
  names = app.split_list(app.command(:image, :names))
  raise "image: expected #{image.name} registered with Tk, got #{names}" unless names.includes?(image.name)

  # Case 3: an image declared inside #add is realized before the new
  # subtree is, exactly as the initial realize orders them.
  added = nil.as(Teek::UI::Image?)
  session.add(:list) do |builder|
    inner = builder.image(image_path)
    added = inner
    builder.label(:added_logo, image: inner.name)
  end
  app.update

  inner_image = added.as(Teek::UI::Image)
  raise "image: expected teek_ui_image_2, got #{inner_image.name}" unless inner_image.name == "teek_ui_image_2"
  inner_size = inner_image.photo.get_size
  raise "image: expected the added image loaded, got #{inner_size}" unless inner_size == {width: 1, height: 1}

  # Case 4: the widget that named an image really displays it - the name
  # a build-time declaration hands out has to survive into the real -image
  # option, which is the whole reason it is allocated that early.
  added_logo = session[:added_logo]
  shown = app.command(added_logo.path, :cget, "-image")
  raise "image: expected -image #{inner_image.name}, got #{shown.inspect}" unless shown == inner_image.name

  # Case 5: a rejected #add drops any image it declared, same as it drops
  # the nodes and vars - the grid child below has no cell, so validation
  # refuses the whole block.
  begin
    session.add(:form) do |builder|
      builder.image(image_path)
      builder.label(:no_cell, text: "nope")
    end
    raise "image: expected ValidationError for a grid child with no cell"
  rescue Teek::UI::ValidationError
  end

  after_rollback = app.split_list(app.command(:image, :names))
  if after_rollback.includes?("teek_ui_image_3")
    raise "image: expected the rolled-back image never to reach Tk, got #{after_rollback}"
  end

  # ...and having never reached Tk, its name is free for the next one.
  reused_name = ""
  session.add(:list) do |builder|
    reused_name = builder.image(image_path).name
    builder.label(:reused_logo, image: reused_name)
  end
  app.update

  unless reused_name == "teek_ui_image_3"
    raise "image: expected the rolled-back name reused, got #{reused_name}"
  end
  final_names = app.split_list(app.command(:image, :names))
  raise "image: expected #{reused_name} registered, got #{final_names}" unless final_names.includes?(reused_name)

  # Case 6: destroying a subtree that owns an image releases its photo -
  # a thumbnail rebuilt on every refresh must not accumulate a live Tk
  # photo per cycle. debug_info's :live_photos count (queried straight
  # from Tk's `image names`, not @images.size) has to track this too,
  # since it's the only leak detector that can see a photo at all -
  # nothing else here is a callback.
  session.add(:list, &.panel(:thumb_host))
  baseline_names = app.split_list(app.command(:image, :names))
  baseline_photos = session.debug_info[:live_photos]?

  10.times do |i|
    session.add(:thumb_host) do |b|
      b.panel(:thumb_row) do |row|
        img = row.image(image_path)
        row.label(:thumb, image: img.name)
      end
    end
    app.update

    during_names = app.split_list(app.command(:image, :names))
    unless during_names.size == baseline_names.size + 1
      raise "image: cycle #{i}: expected one new live photo, got #{during_names} vs baseline #{baseline_names}"
    end
    during_photos = session.debug_info[:live_photos]?
    expected_during = (baseline_photos || 0) + 1
    unless during_photos == expected_during
      raise "image: cycle #{i}: expected debug_info[:live_photos] == #{expected_during}, got #{during_photos.inspect}"
    end

    session[:thumb_row].destroy!(defer: false)
    app.update
  end

  after_names = app.split_list(app.command(:image, :names))
  raise "image: expected image names back to #{baseline_names} after 10 cycles, got #{after_names}" unless after_names == baseline_names

  after_photos = session.debug_info[:live_photos]?
  unless after_photos == baseline_photos
    raise "image: expected debug_info[:live_photos] back to #{baseline_photos.inspect}, got #{after_photos.inspect}"
  end

  app.destroy
  puts "OK"
ensure
  File.delete?(image_path)
end
