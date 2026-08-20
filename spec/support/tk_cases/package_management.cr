require "../tk_test_registry"

# Package management (App#add_package_path/#require_package/
# #package_names/#package_present?/#package_versions) - Tcl's own
# ::auto_path + pkgIndex.tcl mechanism, not a way to eval arbitrary Tcl:
# every name/version/path below goes through #tcl_invoke (one Tcl_Obj
# per argument, Tcl_EvalObjv), never string-interpolated into a script.
#
# Writes a minimal real Tcl package to a fresh temp directory -
# pkgIndex.tcl plus one proc. A unique package name per call matters more
# here than in most fixture helpers: the worker process (and its one Tcl
# interpreter) is shared across every tk_test in the suite, and once Tcl
# `package require`s a given name it stays loaded/cached for that
# interpreter's lifetime - a name reused across tests would let an
# earlier test's cached load mask what a later one is actually checking.
private def write_pkg_fixture(name : String, version : String) : String
  dir = File.tempname("tryst_pkg_test")
  Dir.mkdir_p(dir)
  File.write(File.join(dir, "pkgIndex.tcl"),
    %(package ifneeded #{name} #{version} [list source [file join $dir #{name}.tcl]]\n))
  File.write(File.join(dir, "#{name}.tcl"),
    %(package provide #{name} #{version}\nproc #{name}_hello {} { return "hello from #{name}" }\n))
  dir
end

tk_test "add_package_path and require_package load a package from a fresh directory" do |app|
  dir = write_pkg_fixture("tryst_pkg_basic", "1.0")
  app.add_package_path(dir)

  version = app.require_package("tryst_pkg_basic")
  raise "expected version '1.0', got #{version.inspect}" unless version == "1.0"
  raise "expected the package's own proc to run" unless app.tcl_eval("tryst_pkg_basic_hello") == "hello from tryst_pkg_basic"
end

tk_test "require_package with an explicit version constraint returns that version" do |app|
  dir = write_pkg_fixture("tryst_pkg_versioned", "2.5")
  app.add_package_path(dir)

  version = app.require_package("tryst_pkg_versioned", "2.5")
  raise "expected version '2.5', got #{version.inspect}" unless version == "2.5"
end

tk_test "require_package raises TclError naming the missing package" do |app|
  begin
    app.require_package("tryst_pkg_does_not_exist_xyz")
    raise "expected TclError, got no exception"
  rescue ex : Tryst::TclError
    message = ex.message || ""
    raise "expected the package name in the error, got #{message.inspect}" unless message.includes?("tryst_pkg_does_not_exist_xyz")
  end
end

tk_test "package_present? reflects whether a package has actually been required" do |app|
  dir = write_pkg_fixture("tryst_pkg_presence", "1.0")
  app.add_package_path(dir)

  raise "expected not present before requiring" if app.package_present?("tryst_pkg_presence")
  app.require_package("tryst_pkg_presence")
  raise "expected present after requiring" unless app.package_present?("tryst_pkg_presence")
  raise "expected a made-up name to be absent" if app.package_present?("tryst_pkg_totally_made_up_xyz")
end

tk_test "package_versions lists a fixture package's available version" do |app|
  dir = write_pkg_fixture("tryst_pkg_versions_list", "3.1")
  app.add_package_path(dir)

  versions = app.package_versions("tryst_pkg_versions_list")
  raise "expected ['3.1'], got #{versions.inspect}" unless versions == ["3.1"]
end

tk_test "package_names includes Tk" do |app|
  raise "expected Tk in package_names" unless app.package_names.includes?("Tk")
end

tk_test "add_package_path appends the given path to ::auto_path" do |app|
  path = File.tempname("tryst_pkg_test_autopath")
  app.add_package_path(path)

  auto_path = app.split_list(app.get_variable("::auto_path"))
  raise "expected #{path.inspect} in ::auto_path, got #{auto_path.inspect}" unless auto_path.includes?(path)
end

# opt0.4 ships bundled with Tcl itself (a pure-Tcl script, part of Tcl's
# own standard distribution - no compiled extension, nothing this suite
# installs or vendors) - a real, unmodified package already on
# ::auto_path, not a fixture written above. Not http1.0: upstream Tcl 9
# dropped the legacy pre-namespace http package entirely. opt0.4 is
# still present and pkgIndex.tcl-based on both 8.6 and 9.x, but its
# exact patch version drifts per platform
# (0.4.9 on 8.6, 0.4.9-0.4.10 across 9.x builds seen so far) - unlike
# http1.0's frozen "1.0", so this only pins the major.minor requested,
# not the exact returned/listed version string.
tk_test "require_package/package_present?/package_versions work against a real bundled Tcl package" do |app|
  version = app.require_package("opt", "0.4")
  raise "expected a 0.4.x version, got #{version.inspect}" unless version.starts_with?("0.4")
  raise "expected opt to be present after requiring" unless app.package_present?("opt")
  raise "expected a 0.4.x entry in package_versions, got #{app.package_versions("opt").inspect}" \
    unless app.package_versions("opt").any?(&.starts_with?("0.4"))

  # ::tcl::Lempty is real code from the package, not anything this suite
  # wrote - if it returns the right answer, the package actually loaded
  # and ran, not just registered a version string.
  raise "expected the package's own code to run" unless app.tcl_eval("::tcl::Lempty {}") == "1"
end
