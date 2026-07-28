require "../app"

module Teek
  module UI
    # An event a node wants wired up. target is nil to bind on the node's
    # own widget, or a Symbol naming another node's widget - resolved by
    # the realizer's link pass, after every node in the whole tree has
    # already been created, so a target declared later in the build still
    # resolves correctly (the forward-reference case). subs are
    # Teek::App#bind substitution codes (e.g. [:x, :y]) forwarded to the
    # handler when it fires.
    #
    # handler's type mirrors App#bind's own block signature exactly (see
    # TclArgValue's Proc member in app.cr) - an EventBinding's handler
    # ultimately gets passed straight through to App#bind by the realizer.
    record EventBinding,
      event : String,
      handler : Proc(Array(String), CallbackSignal, Nil),
      target : Symbol? = nil,
      subs : Array(Symbol | String) = [] of Symbol | String
  end
end
