module Teek
  # Registry of per-Tk-widget-type interceptors that App#command consults
  # before falling back to its own generic handling. Each interceptor is a
  # labeled block registered under a widget type string (the same strings
  # used in WIDGET_COMMANDS); App#command looks up the type for the path
  # it was given (see App#record_widget_type) and tries every interceptor
  # registered for that type.
  #
  # An interceptor block receives (app, path, args, kwargs) and must
  # return nil if this call isn't its concern - App#raw_command's Tcl
  # results are always Strings, never nil, so nil is an unambiguous "not
  # mine" sentinel - or the Tcl result if it handled the call itself
  # (typically by calling App#raw_command internally).
  #
  # Multiple widget types can share the same interceptor logic by
  # registering the same block under each type. label is what #command
  # reports if two DIFFERENT interceptors both claim the same call for the
  # same type - it raises AmbiguousCommandError naming both labels rather
  # than silently picking one, so whoever's debugging can tell which
  # interceptors collided.
  #
  # Class-level (one registry for the whole process, like ruby-teek's) -
  # registrations are meant to be permanent, load-time declarations (the
  # built-in menu/tag/canvas interceptors, in later tasks, register
  # themselves once when their files are required), not per-App state.
  class CommandInterceptors
    alias Block = Proc(App, String, Array(TclArgValue), Hash(String, TclArgValue), String?)
    record Entry, label : String, block : Block

    @@interceptors = Hash(String, Array(Entry)).new { |interceptors, type| interceptors[type] = [] of Entry }

    def self.register(type, label, &block : Block) : Nil
      @@interceptors[type.to_s] << Entry.new(label.to_s, block)
    end

    def self.for_type(type) : Array(Entry)
      @@interceptors[type.to_s]
    end
  end
end
