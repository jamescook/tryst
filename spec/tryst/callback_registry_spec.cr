require "../spec_helper"
require "../../src/tryst/callback_registry"

# Pure-logic tests for Tryst::CallbackRegistry - no Tk interpreter needed
# (precedent: ruby-tryst's test/test_callback_registry.rb, which this
# mirrors 1:1). A fake app stub stands in for the real Tryst::App, since
# the registry only ever calls #unregister_callback on it.
private class FakeApp
  getter released = [] of String

  def unregister_callback(id : String) : Nil
    @released << id
  end
end

private def new_registry
  app = FakeApp.new
  registry = Tryst::CallbackRegistry.new(app)
  {registry, app}
end

describe Tryst::CallbackRegistry do
  describe "#reconcile" do
    it "tracks a new key without releasing anything" do
      registry, app = new_registry
      registry.reconcile({:bind, ".e"}) { |before| before.merge({"<Key-a>" => "cb1"}) }
      app.released.should be_empty
    end

    it "releases the prior id when a key is overwritten" do
      registry, app = new_registry
      registry.reconcile({:bind, ".e"}) { |before| before.merge({"<Key-a>" => "cb1"}) }
      registry.reconcile({:bind, ".e"}) { |before| before.merge({"<Key-a>" => "cb2"}) }
      app.released.should eq(["cb1"])
    end

    it "does not release ids at other keys" do
      registry, app = new_registry
      registry.reconcile({:bind, ".e"}) { |before| before.merge({"<Key-a>" => "cb1"}) }
      registry.reconcile({:bind, ".e"}) { |before| before.merge({"<Key-b>" => "cb2"}) }
      app.released.should be_empty
    end

    it "releases a key removed from the returned hash" do
      registry, app = new_registry
      registry.reconcile({:bind, ".e"}) { |before| before.merge({"<Key-a>" => "cb1"}) }
      registry.reconcile({:bind, ".e"}) { |before| before.reject { |k, _| k == "<Key-a>" } }
      app.released.should eq(["cb1"])
    end

    it "removing an untracked key is a safe no-op" do
      registry, app = new_registry
      registry.reconcile({:bind, ".e"}) { |before| before.reject { |k, _| k == "<Key-a>" } }
      app.released.should be_empty
    end

    it "hands an empty hash on the first call" do
      registry, _app = new_registry
      seen = nil
      registry.reconcile({:bind, ".e"}) { |before| seen = before; before }
      seen.should eq({} of String => String)
    end

    it "recompute-from-scratch style releases ids that drop out of the live set" do
      registry, app = new_registry
      registry.reconcile({:menu, ".m"}) { {"cb1" => "cb1", "cb2" => "cb2"} }
      registry.reconcile({:menu, ".m"}) { {"cb2" => "cb2"} }
      app.released.should eq(["cb1"])
    end

    it "recompute-from-scratch style keeps ids that remain live" do
      registry, app = new_registry
      registry.reconcile({:menu, ".m"}) { {"cb1" => "cb1", "cb2" => "cb2"} }
      registry.reconcile({:menu, ".m"}) { {"cb1" => "cb1", "cb2" => "cb2"} }
      app.released.should be_empty
    end

    it "recompute-from-scratch style tracks newly appeared ids without releasing anything" do
      registry, app = new_registry
      registry.reconcile({:menu, ".m"}) { {"cb1" => "cb1"} }
      registry.reconcile({:menu, ".m"}) { {"cb1" => "cb1", "cb2" => "cb2"} }
      app.released.should be_empty
    end

    it "recompute-from-scratch style on an empty live set releases everything tracked" do
      registry, app = new_registry
      registry.reconcile({:menu, ".m"}) { {"cb1" => "cb1", "cb2" => "cb2"} }
      registry.reconcile({:menu, ".m"}) { {} of String => String }
      app.released.sort.should eq(["cb1", "cb2"])
    end
  end

  describe "#forget_all_for_path" do
    it "releases a container" do
      registry, app = new_registry
      registry.reconcile({:bind, ".e"}) { |before| before.merge({"<Key-a>" => "cb1", "<Key-b>" => "cb2"}) }
      registry.forget_all_for_path(".e")
      app.released.sort.should eq(["cb1", "cb2"])
    end

    it "releases every feature sharing the path in one call" do
      registry, app = new_registry
      registry.reconcile({:bind, ".w"}) { |before| before.merge({"<Key-a>" => "cb1"}) }
      registry.reconcile({:menu, ".w"}) { {"cb2" => "cb2"} }
      registry.forget_all_for_path(".w")
      app.released.sort.should eq(["cb1", "cb2"])
    end

    it "does not touch other paths" do
      registry, app = new_registry
      registry.reconcile({:bind, ".a"}) { |before| before.merge({"<Key-a>" => "cb1"}) }
      registry.reconcile({:bind, ".b"}) { |before| before.merge({"<Key-a>" => "cb2"}) }
      registry.forget_all_for_path(".a")
      app.released.should eq(["cb1"])
    end

    it "on an unknown path is a safe no-op" do
      registry, app = new_registry
      registry.forget_all_for_path(".nope")
      app.released.should be_empty
    end

    it "forgets so a second call is a no-op" do
      registry, app = new_registry
      registry.reconcile({:bind, ".e"}) { |before| before.merge({"<Key-a>" => "cb1"}) }
      registry.forget_all_for_path(".e")
      registry.forget_all_for_path(".e")
      app.released.should eq(["cb1"])
    end
  end

  describe "#counts_by_tag" do
    it "is empty when nothing is tracked" do
      registry, _app = new_registry
      registry.counts_by_tag.should eq({} of Symbol => Int32)
    end

    it "counts individual ids not containers" do
      registry, _app = new_registry
      registry.reconcile({:bind, ".e"}) { |before| before.merge({"<Key-a>" => "cb1", "<Key-b>" => "cb2"}) }
      registry.counts_by_tag.should eq({:bind => 2})
    end

    it "sums across every container sharing a tag" do
      registry, _app = new_registry
      registry.reconcile({:bind, ".a"}) { |before| before.merge({"<Key-a>" => "cb1"}) }
      registry.reconcile({:bind, ".b"}) { |before| before.merge({"<Key-a>" => "cb2"}) }
      registry.counts_by_tag.should eq({:bind => 2})
    end

    it "groups separately per tag" do
      registry, _app = new_registry
      registry.reconcile({:bind, ".e"}) { |before| before.merge({"<Key-a>" => "cb1"}) }
      registry.reconcile({:menu, ".m"}) { {"cb2" => "cb2", "cb3" => "cb3"} }
      registry.counts_by_tag.should eq({:bind => 1, :menu => 2})
    end

    it "reflects release via reconcile" do
      registry, _app = new_registry
      registry.reconcile({:bind, ".e"}) { |before| before.merge({"<Key-a>" => "cb1"}) }
      registry.reconcile({:bind, ".e"}) { |before| before.reject { |k, _| k == "<Key-a>" } }
      registry.counts_by_tag.should eq({} of Symbol => Int32)
    end

    it "reflects release via forget_all_for_path" do
      registry, _app = new_registry
      registry.reconcile({:bind, ".e"}) { |before| before.merge({"<Key-a>" => "cb1"}) }
      registry.forget_all_for_path(".e")
      registry.counts_by_tag.should eq({} of Symbol => Int32)
    end
  end
end
