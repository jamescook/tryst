require "../spec_helper"

# Pure value math - no App/Tk/ThorVG involved at all, so this runs
# without ever touching the shared TK_APP. See value_slider_spec.cr for
# everything that needs a live widget.
describe Tryst::ValueSlider do
  describe ".snap" do
    it "rounds to the nearest step" do
      Tryst::ValueSlider.snap(7.3, 0.0, 100.0, 1.0).should eq 7.0
      Tryst::ValueSlider.snap(7.6, 0.0, 100.0, 1.0).should eq 8.0
    end

    it "steps from min, not from zero" do
      Tryst::ValueSlider.snap(6.4, 5.0, 100.0, 2.0).should eq 7.0
      Tryst::ValueSlider.snap(9.1, 5.0, 100.0, 2.0).should eq 9.0
    end

    it "clamps below min and above max after snapping" do
      Tryst::ValueSlider.snap(-40.0, 0.0, 100.0, 1.0).should eq 0.0
      Tryst::ValueSlider.snap(500.0, 0.0, 100.0, 1.0).should eq 100.0
    end

    it "handles a fractional step" do
      Tryst::ValueSlider.snap(1.02, 0.5, 2.0, 0.05).should eq 1.0
    end
  end
end
