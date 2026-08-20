require "../spec_helper"
require "../../src/tryst/command_interceptors"
# An interceptor's own signature names App, which command_interceptors.cr
# doesn't require itself (App requires IT, not the other way round).
require "../../src/tryst/app"

# Pure-logic tests for Tryst::CommandInterceptors's registry itself - no Tk
# interpreter needed (precedent: ruby-tryst has no dedicated test file for
# the registry alone, since App/menu/tag/canvas integration is covered by
# their own interceptor-specific tests in later tasks). This just proves
# the registry mechanics App#command relies on: empty passthrough,
# registration, and multiple entries stacking under the same type.
#
# CommandInterceptors is a class-level (whole-process) registry, so a
# unique, clearly-fake type string is used throughout to avoid leaking
# state that could affect any other spec or tk_test case sharing this
# process/the persistent worker.
describe Tryst::CommandInterceptors do
  describe ".for_type" do
    it "returns an empty array for a type with no registered interceptors" do
      Tryst::CommandInterceptors.for_type("ctk_spec_never_registered").should be_empty
    end

    # A lookup is a read - it must not insert an empty Array under a
    # missed type, or App#command would grow the registry on every call
    # for a type nobody intercepts.
    it "a lookup that misses doesn't stop a later registration taking" do
      Tryst::CommandInterceptors.for_type("ctk_spec_miss_then_register").should be_empty
      Tryst::CommandInterceptors.register("ctk_spec_miss_then_register", "late") { |_app, _path, _args, _kwargs| nil }

      Tryst::CommandInterceptors.for_type("ctk_spec_miss_then_register").map(&.label).should eq(["late"])
    end

    it "hands back the same empty result for every type it misses" do
      first = Tryst::CommandInterceptors.for_type("ctk_spec_miss_one")
      second = Tryst::CommandInterceptors.for_type("ctk_spec_miss_two")

      first.should be_empty
      second.should be_empty
      # One shared empty rather than an allocation per miss - which is
      # only safe because for_type's result is read, never appended to.
      first.should be(second)
    end
  end

  describe ".register" do
    it "makes the entry findable via .for_type, with the given label" do
      Tryst::CommandInterceptors.register("ctk_spec_fake_type_a", "spec-label") { |_app, _path, _args, _kwargs| nil }

      entries = Tryst::CommandInterceptors.for_type("ctk_spec_fake_type_a")
      entries.size.should eq(1)
      entries.first.label.should eq("spec-label")
    end

    it "stacks multiple registrations under the same type" do
      Tryst::CommandInterceptors.register("ctk_spec_fake_type_b", "first") { |_app, _path, _args, _kwargs| nil }
      Tryst::CommandInterceptors.register("ctk_spec_fake_type_b", "second") { |_app, _path, _args, _kwargs| nil }

      entries = Tryst::CommandInterceptors.for_type("ctk_spec_fake_type_b")
      entries.map(&.label).should eq(["first", "second"])
    end

    it "accepts a Symbol type/label, converting both to String" do
      Tryst::CommandInterceptors.register(:ctk_spec_fake_type_c, :sym_label) { |_app, _path, _args, _kwargs| nil }

      entries = Tryst::CommandInterceptors.for_type("ctk_spec_fake_type_c")
      entries.first.label.should eq("sym_label")
    end
  end
end
