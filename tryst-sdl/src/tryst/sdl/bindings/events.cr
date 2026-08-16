require "./core"

# SDL3's event pump. Reopens LibSDL; the @[Link] lives in core.cr.
lib LibSDL
  # Services SDL's own connection to the window system: reads whatever
  # has arrived and sends whatever SDL has queued.
  #
  # Matters here because SDL keeps its OWN display connection, separate
  # from Tk's. Pumping Tk does not move SDL's traffic, so anything SDL
  # has queued about a window sits there until something makes it go.
  fun pump_events = SDL_PumpEvents
end
