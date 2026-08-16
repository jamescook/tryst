require "compress/zlib"
require "digest/crc32"
require "../../src/tryst-sdl"

# Standalone verification for image loading (SDL3_image) and TrueType
# text (SDL3_ttf) against a real renderer. Its own process for the same
# reason viewport_fixture.cr is: Tk up, then SDL video, only reliably
# true at the start of a fresh program. A `raise` is the assertion here -
# the exit code is what spec/tryst/sdl/image_text_spec.cr checks.

# A minimal valid PNG, generated rather than committed - same reasoning
# as WavFixture: a binary asset in the repo is a thing nobody can
# review. One filter-none RGBA scanline per row, zlib-wrapped (a raw
# PNG requires the zlib container even with no real compression asked
# for) - the least libpng will still decode.
def solid_png(path : String, width : Int32, height : Int32,
              r : UInt8, g : UInt8, b : UInt8, a : UInt8 = 255_u8) : String
  raw = IO::Memory.new
  height.times do
    raw.write_byte(0_u8) # filter: None
    width.times do
      raw.write_byte(r)
      raw.write_byte(g)
      raw.write_byte(b)
      raw.write_byte(a)
    end
  end

  zlib = IO::Memory.new
  Compress::Zlib::Writer.open(zlib, &.write(raw.to_slice))

  ihdr = IO::Memory.new
  ihdr.write_bytes(width.to_u32, IO::ByteFormat::BigEndian)
  ihdr.write_bytes(height.to_u32, IO::ByteFormat::BigEndian)
  ihdr.write_byte(8_u8) # bit depth
  ihdr.write_byte(6_u8) # color type: RGBA
  ihdr.write_byte(0_u8) # compression
  ihdr.write_byte(0_u8) # filter
  ihdr.write_byte(0_u8) # interlace

  File.open(path, "w") do |file|
    file.write(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    write_png_chunk(file, "IHDR", ihdr.to_slice)
    write_png_chunk(file, "IDAT", zlib.to_slice)
    write_png_chunk(file, "IEND", Bytes.empty)
  end
  path
end

private def write_png_chunk(file : File, type : String, data : Bytes) : Nil
  type_bytes = type.to_slice
  file.write_bytes(data.size.to_u32, IO::ByteFormat::BigEndian)
  file.write(type_bytes)
  file.write(data)
  file.write_bytes(Digest::CRC32.checksum(type_bytes + data), IO::ByteFormat::BigEndian)
end

app = Tryst::App.new(title: "image/text fixture")
app.show
app.update

viewport = Tryst::SDL::Viewport.new(app, width: 160, height: 120, name: "vp_image_text")
renderer = viewport.renderer

blue = Tryst::SDL::Color.new(0, 0, 255)
white = Tryst::SDL::Color.new(255, 255, 255)

# --- Images ------------------------------------------------------------

png_dir = File.join(Dir.tempdir, "tryst-sdl-image-fixture-#{Process.pid}")
Dir.mkdir_p(png_dir)
png_path = solid_png(File.join(png_dir, "green.png"), 8, 8, 0_u8, 255_u8, 0_u8)

begin
  # Case I1: dimensions come from the decoded file, not asked for.
  image = renderer.load_image(png_path)
  begin
    raise "image: expected 8x8, got #{image.width}x#{image.height}" unless image.width == 8 && image.height == 8
    raise "image: expected a live texture" if image.destroyed?

    # Case I2: it actually renders.
    renderer.clear(blue)
    renderer.copy(image, dest: Tryst::SDL::Rect.new(0, 0, image.width * 4, image.height * 4))
    renderer.read_pixels do |pixels|
      got = pixels[image.width * 2, image.height * 2]
      raise "image: expected the loaded PNG to be green, got #{got}" unless got.g > 200 && got.r < 60
    end
  ensure
    image.destroy
  end

  # Case I3: Texture.from_file is load_image under another name.
  via_from_file = Tryst::SDL::Texture.from_file(renderer, png_path)
  begin
    raise "image: expected from_file to match load_image's size" unless via_from_file.width == 8
  ensure
    via_from_file.destroy
  end

  # Case I4: a missing file is a raise, not a null texture silently handed back.
  begin
    renderer.load_image(File.join(png_dir, "does_not_exist.png"))
    raise "image: expected a missing file to be refused"
  rescue ex : Tryst::SDL::Error
    raise "image: expected an IMG_LoadTexture complaint, got #{ex.message.inspect}" unless ex.message.to_s.includes?("IMG_LoadTexture")
  end
ensure
  Dir.each_child(png_dir) { |name| File.delete?(File.join(png_dir, name)) }
  Dir.delete?(png_dir)
end

# --- Text ----------------------------------------------------------------

font_path = "spec/assets/test_font.ttf"

font = renderer.load_font(font_path, 32)
begin
  # Case F1: measure and ascent work without rendering anything.
  measured_w, measured_h = font.measure("I")
  raise "text: expected a positive measured size, got #{measured_w}x#{measured_h}" unless measured_w > 0 && measured_h > 0
  raise "text: expected a positive ascent, got #{font.ascent}" unless font.ascent > 0

  # Case F2: a fully transparent glyph (space) must stay exactly the
  # background colour - the thing premultiplying the surface exists to
  # guarantee. Without it, TTF_RenderText_Blended's (fg_color, A=0)
  # background pixels would bleed fg_color through BlendPremultiplied.
  blank = font.render_text(" ", white)
  begin
    raise "text: expected the space glyph to have real dimensions" unless blank.width > 0 && blank.height > 0
    renderer.clear(blue)
    renderer.copy(blank, dest: Tryst::SDL::Rect.new(0, 0, blank.width, blank.height))
    renderer.read_pixels do |pixels|
      got = pixels[blank.width // 2, blank.height // 2]
      raise "text: expected a space glyph to leave the background untouched, got #{got}" unless got == blue
    end
  ensure
    blank.destroy
  end

  # Case F3: an inked glyph draws close to the requested colour, sampled
  # at cap-height rather than the surface's vertical centre - the full
  # line box includes descender space "I" never reaches.
  glyph = font.render_text("I", white)
  begin
    renderer.clear(blue)
    renderer.copy(glyph, dest: Tryst::SDL::Rect.new(0, 0, glyph.width, glyph.height))
    renderer.read_pixels do |pixels|
      sample_y = (font.ascent // 2).clamp(0, glyph.height - 1)
      got = pixels[glyph.width // 2, sample_y]
      unless got.r > 200 && got.g > 200 && got.b > 200
        raise "text: expected the glyph stroke to render near-white, got #{got}"
      end
    end
  ensure
    glyph.destroy
  end

  # Case F4: Renderer#draw_text is the one-shot render-and-copy path.
  measured_w, measured_h = font.measure("I")
  renderer.clear(blue)
  renderer.draw_text(5, 5, "I", font, color: white)
  renderer.read_pixels do |pixels|
    sample_y = 5 + (font.ascent // 2).clamp(0, measured_h - 1)
    got = pixels[5 + measured_w // 2, sample_y]
    unless got.r > 200 && got.g > 200 && got.b > 200
      raise "text: expected draw_text's glyph stroke to render near-white, got #{got}"
    end
  end

  # Case F5: destroy is idempotent, and unusable afterwards.
  font.destroy
  font.destroy
  raise "text: expected destroyed?" unless font.destroyed?
  begin
    font.measure("I")
    raise "text: expected a destroyed font to refuse use"
  rescue ex : Tryst::SDL::Error
    raise "text: expected 'destroyed', got #{ex.message.inspect}" unless ex.message.to_s.includes?("destroyed")
  end
ensure
  font.destroy
end

# Case F6: a missing font file is a raise.
begin
  renderer.load_font("/nonexistent/path/to/font.ttf", 16)
  raise "text: expected a missing font file to be refused"
rescue ex : Tryst::SDL::Error
  raise "text: expected a TTF_OpenFont complaint, got #{ex.message.inspect}" unless ex.message.to_s.includes?("TTF_OpenFont")
end

viewport.destroy
app.destroy
puts "OK"
