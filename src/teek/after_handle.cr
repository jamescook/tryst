module Teek
  # Wraps a Tcl `after` command's id string together with the callback id
  # registered for it, so App#after_cancel can release both. Ruby-teek
  # staples the callback id onto the after-id String itself via
  # instance_variable_set (any Ruby object can carry ad-hoc ivars, even a
  # String); Crystal has no equivalent for a plain String, so this is a
  # real composite object instead. #to_s returns the raw Tcl after-id, so
  # it can still be interpolated into a Tcl script the same way
  # ruby-teek's stapled-String after_id can (e.g. "after cancel #{handle}").
  class AfterHandle
    getter tcl_id : String
    property cb_id : String?

    def initialize(@tcl_id : String, @cb_id : String? = nil)
    end

    def to_s(io : IO) : Nil
      io << @tcl_id
    end
  end
end
