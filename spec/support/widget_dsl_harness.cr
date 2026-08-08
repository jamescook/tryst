require "../../src/teek/ui/widget_dsl"

# A minimal stand-in for Teek::UI::Session, providing just the state
# contract WidgetDSL itself needs (@document, @stack, #build_open?) -
# lets WidgetDSL's core append_leaf/append_container/@stack machinery be
# spec'd without needing a real, fully-realized app. Session itself now
# exists (src/teek/ui/session.cr); this harness stays useful precisely
# because it skips constructing a real Teek::App, so specs built against
# it stay headless - see the project's own "provisional spec layout"
# precedent (spec/support/tk_cases.cr's own doc comment) for the general
# pattern this follows.
class WidgetDslHarness
  include Teek::UI::WidgetDSL

  getter document : Teek::UI::Document
  @build_open = true

  def initialize
    @document = Teek::UI::Document.new
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
