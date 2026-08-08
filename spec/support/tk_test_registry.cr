require "../../src/teek"

{% unless flag?(:tk_worker_mode) %}
  require "./tk_worker_client"
{% end %}

module TkTest
  REGISTRY = {} of String => Proc(Teek::App, Nil)
end

# Registers a named Tk test case. The block runs against a shared,
# already-initialized Teek::App (Tk_Init can only happen once per
# process - see spec/support/tk_worker.cr) - never construct a
# Teek::App of your own inside a tk_test block. App#interp exposes the
# underlying Interp for anything that doesn't have an App-level
# equivalent yet (create_widget/pack/bind/simulate_event/wait_until/
# queue_for_main/pump_once - all Interp-only conveniences until their
# own tasks land at the App layer).
#
# Compiles into two different roles depending on how the CURRENT binary
# is built, without the call site ever changing:
#  - worker mode (`crystal build/run -D tk_worker_mode ...`): the block
#    is real and lives in TkTest::REGISTRY, dispatched by name over
#    spec/support/tk_worker.cr's stdin/stdout protocol.
#  - spec mode (plain `crystal spec`): registered the same way (so the
#    block is still fully compiled/type-checked), but it's never called
#    in this process - there's no Tk_Init here at all. Instead a real
#    Crystal::Spec example is generated that asks the persistent worker
#    (TkWorkerClient) to run this test by name and asserts on the result.
#
# darwin_only: true marks a case that only has meaningful behavior to
# assert on macOS (currently the Aqua-only appearance/dark-mode API).
# Off macOS it's reported as pending rather than dropped, so the suite
# still says out loud that it didn't run - and the block is registered
# either way, so it stays compiled and type-checked on every platform.
def tk_test(name : String, *, darwin_only : Bool = false, &block : Teek::App -> Nil) : Nil
  TkTest::REGISTRY[name] = block

  {% unless flag?(:tk_worker_mode) %}
    if darwin_only && !Teek.platform.darwin?
      pending name
    else
      it name do
        result = TkWorkerClient.run(name)
        raise "#{name} failed: #{result.error}" unless result.success?
      end
    end
  {% end %}
end
