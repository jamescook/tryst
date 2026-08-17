require "../../src/tryst/ui/widget_dsl"

# A minimal stand-in for Tryst::UI::Session, providing just the state
# contract WidgetDSL itself needs (@document, @stack, #build_open?) -
# lets WidgetDSL's core append_leaf/append_container/@stack machinery be
# spec'd without needing a real, fully-realized app. Session itself now
# exists (src/tryst/ui/session.cr); this harness stays useful precisely
# because it skips constructing a real Tryst::App, so specs built against
# it stay headless - see the project's own "provisional spec layout"
# precedent (tk_test_registry.cr's own doc comment) for the general
# pattern this follows.
class WidgetDslHarness
  include Tryst::UI::WidgetDSL

  getter document : Tryst::UI::Document
  @build_open = true

  def initialize
    @document = Tryst::UI::Document.new
    @stack = [@document.root]
  end

  # WidgetDSL's own abstract def requires an explicit Bool return type,
  # which the property? macro doesn't emit - written by hand instead.
  def build_open? : Bool
    @build_open
  end

  def build_open=(@build_open : Bool)
  end
end
