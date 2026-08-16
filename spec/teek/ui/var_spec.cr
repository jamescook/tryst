require "../../spec_helper"
require "../../../src/teek/ui/var"

# Pure-logic tests for Teek::UI::Var - no Tk interpreter needed. Mirrors
# ruby-teek's teek-ui/test/test_var.rb, which covers only the pre-realize
# surface (name allocation, #value/#value= raising before realize,
# #on_change queueable and chainable) - unlike Realizer/Handle, Var has
# no FakeApp-substitutable seam (it holds @app as the concrete Teek::App,
# see var.cr's own doc comment for why), so its real value/coercion/
# change-trace behavior is only ever exercised against real Tk instead -
# see spec/standalone/reactive_vars_fixture.cr, mirroring ruby's
# test_reactive_vars.rb.
describe Teek::UI::Var do
  it "name is the allocated Tcl variable name" do
    var = Teek::UI::Var.new("::teek_ui_var_1", 5)

    var.name.should eq("::teek_ui_var_1")
  end

  it "value raises before realize" do
    var = Teek::UI::Var.new("::teek_ui_var_1", 5)

    expect_raises(Teek::UI::NotRealizedError) { var.value }
  end

  it "value= raises before realize" do
    var = Teek::UI::Var.new("::teek_ui_var_1", 5)

    expect_raises(Teek::UI::NotRealizedError) { var.value = 6 }
  end

  it "on_change is queueable before realize and returns self" do
    var = Teek::UI::Var.new("::teek_ui_var_1", 5)

    result = var.on_change { |value| value }

    result.should be(var)
  end

  it "clear_on_change empties the queued handlers" do
    var = Teek::UI::Var.new("::teek_ui_var_1", 5)
    var.on_change { |value| value }

    var.clear_on_change

    # Nothing observable pre-realize besides not raising - the real
    # "no handler fires afterward" behavior needs a live trace, covered
    # in reactive_vars_fixture.cr.
    var.clear_on_change
  end

  # #unrealize deletes the backing Tcl variable/trace/callback, which
  # needs real Tk to prove (see reactive_vars_fixture.cr) - this only
  # covers the pre-realize edge, where there's nothing to tear down yet,
  # and needs no interpreter either way.
  it "unrealize before realize is a safe no-op" do
    var = Teek::UI::Var.new("::teek_ui_var_1", 5)

    var.unrealize

    expect_raises(Teek::UI::NotRealizedError) { var.value }
  end
end
