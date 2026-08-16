module Tryst
  # What a timer does with an exception raised by its block, when no
  # handler proc was given.
  enum ErrorPolicy
    # Surface the exception from the next App#update.
    Raise

    # Swallow it.
    Ignore
  end

  # An on_error: handler - called with the exception instead of applying
  # a policy. Only a handler lets a repeating timer keep running; both
  # policies stop it, and differ just in whether the exception surfaces.
  #
  # A policy and a handler are separate overloads rather than one
  # `ErrorPolicy | Proc` parameter, and that is load-bearing. A proc
  # literal whose body always raises has type Proc(Exception, NoReturn),
  # which is accepted wherever Proc(Exception, Nil) is expected but is
  # NOT an is_a?(Proc(Exception, Nil)) at runtime. Put one in a union and
  # every branch testing for the proc silently fails to match - with an
  # exhaustive `case ... in` that means falling through to unreachable
  # code and hanging, not an error. Keeping the two apart means nothing
  # ever has to type-test a Proc.
  alias ErrorHandler = Proc(Exception, Nil)
end
