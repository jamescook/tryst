module Teek
  # A pending Tcl `after` command: its Tcl after-id, plus the callback id
  # registered to run when it fires, so App#after_cancel can release both.
  # #to_s is the bare after-id, so a handle drops straight into a Tcl
  # script - "after cancel #{handle}".
  record AfterHandle, tcl_id : String, cb_id : String? = nil do
    def to_s(io : IO) : Nil
      io << @tcl_id
    end
  end
end
