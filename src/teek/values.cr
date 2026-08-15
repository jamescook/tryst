require "./interp"

lib LibTcl
  # objc is TclSize-shaped in both - see interp.cr's TclSize/#eval comment.
  # list_obj_append_element/get_boolean_from_obj are plain int in both
  # versions (checked directly against Tcl 9.0.3's tclDecls.h).
  fun new_list_obj = Tcl_NewListObj(objc : TclSize, objv : Obj**) : Obj*
  fun list_obj_append_element = Tcl_ListObjAppendElement(interp : Interp*, list_ptr : Obj*, obj : Obj*) : LibC::Int
  fun list_obj_get_elements = Tcl_ListObjGetElements(interp : Interp*, list_ptr : Obj*, objc : TclSize*, objv : Obj***) : LibC::Int
  fun get_boolean_from_obj = Tcl_GetBooleanFromObj(interp : Interp*, obj : Obj*, value : LibC::Int*) : LibC::Int
end

module Teek
  @@utility_interp = Pointer(LibTcl::Interp).null
  @@utility_mutex = Mutex.new

  # Bare Tcl interpreter (no Tk) backing .split_list/.make_list/.tcl_to_bool
  # below, so they work without constructing a full Teek::App/Interp first -
  # mirrors ruby-teek's utility_interp (ext/teek/tcltkbridge.c), created once
  # when the C extension loads there. Created lazily here on first use
  # instead (Crystal has no module-load-time hook to mirror that exactly),
  # and every access - creation and use alike - goes through
  # @@utility_mutex: unlike Ruby, where MRI's GVL serializes all Ruby-level
  # execution unless explicitly released, Crystal's
  # Fiber::ExecutionContext::Isolated contexts are real OS threads with
  # nothing enforcing that serialization, and a bare Tcl_Interp* is not
  # safe to touch concurrently from more than one thread (nor is the
  # lazy-create check itself safe unsynchronized). These calls are fast,
  # non-blocking pure value conversions, so lock contention is a non-issue.
  private def self.utility_interp : LibTcl::Interp*
    return @@utility_interp unless @@utility_interp.null?

    LibTcl.find_executable("crystal_teek")
    ptr = LibTcl.create_interp
    raise TclError.new("Tcl_CreateInterp returned NULL (utility interp)") if ptr.null?

    # Tcl_Init was skipped here for a long time since a bare interp
    # doesn't need init.tcl's library procs for pure Tcl_Obj value
    # conversion - but ruby-teek calls it (ext/teek/tcltkbridge.c,
    # Init_tcltklib) on this exact kind of bare utility interp too, not
    # only its Tk-backed ones, and skipping it here is what a Tcl 9
    # allocator segfault in Tcl_NewStringObj traced back to (a
    # process/interp-scoped step Tcl 9's threading-aware allocator
    # depends on that 8.6 tolerated going without).
    code = LibTcl.init(ptr)
    raise TclError.new("Tcl_Init failed (utility interp)") unless code == Interp::TCL_OK

    @@utility_interp = ptr
  end

  # Parses a Tcl list string into an array of strings - does not recursively
  # parse nested lists. nil/empty input returns an empty array. Mirrors
  # ruby-teek's Teek.split_list (ext/teek/tcltkbridge.c).
  def self.split_list(str : String?) : Array(String)
    return [] of String if str.nil? || str.empty?

    @@utility_mutex.synchronize do
      # utility_interp first, even though Tcl_NewStringObj takes no interp
      # argument and doesn't look like it needs one forced into existence -
      # on Tcl 9 it crashes in Tcl_Alloc if no interpreter has ever been
      # created in this process yet (its threading-aware allocator turns
      # out to be interp-creation-initialized; 8.6's tolerates going
      # without). Confirmed directly: calling Tcl_NewStringObj before any
      # Tcl_CreateInterp segfaults under Tcl 9, works fine under 8.6.
      interp = utility_interp
      obj = LibTcl.new_string_obj(str, LibTcl::TclSize.new(str.bytesize))
      LibTcl.db_incr_ref_count(obj, __FILE__, __LINE__)

      code = LibTcl.list_obj_get_elements(interp, obj, out objc, out objv)
      if code != 0
        message = String.new(LibTcl.get_string(LibTcl.get_obj_result(interp)))
        LibTcl.db_decr_ref_count(obj, __FILE__, __LINE__)
        raise TclError.new("invalid Tcl list: #{message}")
      end

      result = (0...objc).map do |i|
        len = LibTcl::TclSize.new(0)
        ptr = LibTcl.get_string_from_obj(objv[i], pointerof(len))
        String.new(ptr, len)
      end
      LibTcl.db_decr_ref_count(obj, __FILE__, __LINE__)
      result
    end
  end

  # A typed splat (`*args : String`) rejects a zero-argument call outright
  # (verified directly) - unlike an untyped splat, which just yields an
  # empty Enumerable - so the empty case needs its own overload instead of
  # an `args.empty?` guard inside the main one below.
  def self.make_list : String
    ""
  end

  # Builds a properly Tcl-quoted list string from the given elements (only
  # where quoting is actually needed - Tcl's own list-formatting rules).
  # Mirrors ruby-teek's Teek.make_list (ext/teek/tcltkbridge.c).
  def self.make_list(*args : String) : String
    make_list(args)
  end

  # Same as the splat overload above, for a runtime-sized collection (e.g.
  # already have an Array(String) in hand, rather than individual
  # arguments) - a splat can't be applied to a runtime Array directly
  # (verified directly: "argument to splat must be a tuple"), the same
  # reason Interp#tcl_invoke has this same pair of overloads.
  def self.make_list(args : Enumerable(String)) : String
    return "" if args.empty?

    @@utility_mutex.synchronize do
      # See split_list's comment on why utility_interp is forced first.
      interp = utility_interp
      list_obj = LibTcl.new_list_obj(0, Pointer(Pointer(LibTcl::Obj)).null)
      LibTcl.db_incr_ref_count(list_obj, __FILE__, __LINE__)

      args.each do |arg|
        elem = LibTcl.new_string_obj(arg, LibTcl::TclSize.new(arg.bytesize))
        LibTcl.list_obj_append_element(interp, list_obj, elem)
      end

      len = LibTcl::TclSize.new(0)
      ptr = LibTcl.get_string_from_obj(list_obj, pointerof(len))
      result = String.new(ptr, len)
      LibTcl.db_decr_ref_count(list_obj, __FILE__, __LINE__)
      result
    end
  end

  # Converts a Tcl boolean string ("1"/"0", "true"/"false", "yes"/"no",
  # "on"/"off", any numeric value, case-insensitive) to a Bool. Mirrors
  # ruby-teek's Teek.tcl_to_bool (ext/teek/tcltkbridge.c).
  def self.tcl_to_bool(str : String) : Bool
    @@utility_mutex.synchronize do
      # See split_list's comment on why utility_interp is forced first.
      interp = utility_interp
      obj = LibTcl.new_string_obj(str, LibTcl::TclSize.new(str.bytesize))
      LibTcl.db_incr_ref_count(obj, __FILE__, __LINE__)

      code = LibTcl.get_boolean_from_obj(interp, obj, out bval)
      if code != 0
        message = String.new(LibTcl.get_string(LibTcl.get_obj_result(interp)))
        LibTcl.db_decr_ref_count(obj, __FILE__, __LINE__)
        raise TclError.new(message)
      end

      LibTcl.db_decr_ref_count(obj, __FILE__, __LINE__)
      bval != 0
    end
  end

  # Converts a Ruby-ish truthy/falsy value to a Tcl boolean string ("1" or
  # "0") - only nil/false are falsy, same as Crystal's own if/ternary
  # truthiness. Pure Crystal, no Tcl interpreter involved. Mirrors
  # ruby-teek's Teek.bool_to_tcl (lib/teek.rb).
  def self.bool_to_tcl(val) : String
    val ? "1" : "0"
  end
end
