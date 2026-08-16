module Tryst
  # Tracks callback ids scoped to something narrower than a whole widget -
  # keyed by (container, key) pairs - so they can be released again
  # without waiting for a <Destroy> that may never come for the thing the
  # callback is actually attached to (an event binding, a menu entry,
  # ...). A single instance is shared across every feature that needs
  # this; callers namespace their own container keys (by convention,
  # {feature_tag, path} tuples) so two features tracking the same
  # underlying path never collide.
  #
  # There is exactly one way to keep the registry in sync: #reconcile.
  # Its block is handed the {key => id} hash tracked last time and must
  # return the {key => id} hash that should be tracked now; whatever id
  # drops out between the two gets released. What the block *does* with
  # the hash it's handed is entirely up to the caller - reuse its values
  # as a starting point for a cheap in-memory update (nothing external
  # can silently change an event binding), or ignore it and recompute the
  # truth from scratch by asking Tk (Tk silently renumbers menu entries,
  # so nothing short of asking can be trusted there). The registry itself
  # never knows or cares which one a caller chose.
  #
  # The one hard rule either way: the returned hash must be a DIFFERENT
  # object from the one the block was handed - e.g. before.merge(...),
  # never before.merge!(...) returned as-is (Crystal's Hash#merge is
  # already non-mutating, so this is naturally satisfied as long as a
  # caller doesn't hand back the same Hash instance it was given).
  # Released ids are computed as before.values - after.values; if a
  # caller mutated before in place and returned that same object, before
  # and after would be identical by the time that subtraction runs, so
  # any id that was dropped or replaced would silently never be released
  # - a leak, the exact thing this class exists to prevent.
  #
  # #forget_all_for_path is the only thing a <Destroy> handler needs to
  # call: it releases every container ever registered under a path,
  # regardless of which feature created it, via a reverse index built
  # automatically as a side effect of #reconcile.
  #
  # Generic over App so this can be tested against a fake app stub with
  # no Tk interpreter needed (see spec/tryst/callback_registry_spec.cr) -
  # the registry only ever calls #unregister_callback on it.
  #
  # Known deviation from ruby-tryst, not yet revisited: ruby-tryst's
  # @entries is a plain untyped Hash (Hash.new { |h, k| h[k] = {} }) with
  # no restriction at all on the inner hash's key type, since Ruby never
  # requires one - CanvasBindInterceptor's Ruby source uses a real
  # 2-element Array ([tag_or_id, seq]) as a key directly. #reconcile here
  # is narrowed to Hash(String, String) because that's what every
  # consumer needed when this class was first ported (bind's
  # event_str => cb, menu's id => id) - not a deliberate scope decision,
  # just the concrete type Crystal's static typing forced a choice on.
  # CanvasBindInterceptor (src/tryst/canvas_bind_interceptor.cr), the
  # first consumer that actually needs a composite key, works around
  # this by encoding a (tag_or_id, seq) pair as one space-joined String
  # key rather than widening this class - revisit (e.g. a generic
  # #reconcile(container, &block : Hash(K, String) -> Hash(K, String))
  # via `forall K`) if more consumers hit the same wall.
  class CallbackRegistry(App)
    alias Container = Tuple(Symbol, String)

    def initialize(@app : App)
      @entries = Hash(Container, Hash(String, String)).new { |entries, container| entries[container] = {} of String => String }
      @containers_by_path = Hash(String, Set(Container)).new { |containers, path| containers[path] = Set(Container).new }
    end

    # Yields the {key => id} hash tracked for *container* as of the last
    # call (empty on the first call). The block must return the
    # {key => id} hash that should be tracked now.
    def reconcile(container : Container, & : Hash(String, String) -> Hash(String, String)) : Nil
      track(container)
      before = @entries[container]
      after = yield before
      (before.values - after.values).each { |id| @app.unregister_callback(id) }
      @entries[container] = after
    end

    # Release every callback tracked under any container registered for
    # *path*, regardless of which feature created it, and forget them.
    def forget_all_for_path(path : String) : Nil
      containers = @containers_by_path.delete(path)
      return unless containers
      containers.each do |container|
        ids = @entries.delete(container)
        ids.try &.each_value { |id| @app.unregister_callback(id) }
      end
    end

    # Diagnostic aggregate, not itself load-bearing for cleanup - a live
    # snapshot of how many tracked callback ids currently exist, grouped
    # by the tag every #reconcile container is already keyed on (:bind,
    # :menu, :canvas_bind, :tag_bind, :widget_option, :wm_protocol, ...).
    # Counts individual ids, not containers - a single container can hold
    # several (e.g. one widget bound to several events). A tag with
    # nothing currently tracked under it is simply absent from the
    # result, not present with a zero count.
    def counts_by_tag : Hash(Symbol, Int32)
      counts = Hash(Symbol, Int32).new(0)
      @entries.each do |(tag, _path), ids|
        counts[tag] += ids.size unless ids.empty?
      end
      counts
    end

    # Convention, not a type check: every container is {feature_tag, path}.
    private def track(container : Container) : Nil
      @containers_by_path[container[1]] << container
    end
  end
end
