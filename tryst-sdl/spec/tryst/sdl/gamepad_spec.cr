require "../../spec_helper"

# Everything here runs against a virtual gamepad (.attach_virtual), never
# real hardware - the point of the virtual-device API, and the only way
# this suite can exercise input at all in a container with nothing
# plugged in. Assertions that count/enumerate connected gamepads check
# that the virtual one is AMONG the results rather than the only one,
# since a developer's machine may have a real controller plugged in too.
describe Tryst::SDL::Gamepad do
  describe ".apply_dead_zone" do
    it "zeroes a value within the threshold" do
      Tryst::SDL::Gamepad.apply_dead_zone(500).should eq(0)
      Tryst::SDL::Gamepad.apply_dead_zone(-500).should eq(0)
    end

    it "passes a value at or beyond the threshold through unchanged" do
      Tryst::SDL::Gamepad.apply_dead_zone(8_000).should eq(8_000)
      Tryst::SDL::Gamepad.apply_dead_zone(-9_000).should eq(-9_000)
    end

    it "takes an explicit threshold" do
      Tryst::SDL::Gamepad.apply_dead_zone(100, threshold: 50).should eq(100)
      Tryst::SDL::Gamepad.apply_dead_zone(40, threshold: 50).should eq(0)
    end
  end

  describe ".attach_virtual" do
    it "creates a device .ids and .open can see, and refuses a second one" do
      id = Tryst::SDL::Gamepad.attach_virtual
      begin
        Tryst::SDL::Gamepad.ids.should contain(id)
        Tryst::SDL::Gamepad.virtual_id.should eq(id)

        expect_raises(Tryst::SDL::Error, /already attached/) do
          Tryst::SDL::Gamepad.attach_virtual
        end
      ensure
        Tryst::SDL::Gamepad.detach_virtual
      end
    end
  end

  describe ".detach_virtual" do
    it "is idempotent, and clears .virtual_id" do
      Tryst::SDL::Gamepad.attach_virtual
      Tryst::SDL::Gamepad.detach_virtual
      Tryst::SDL::Gamepad.detach_virtual
      Tryst::SDL::Gamepad.virtual_id.should be_nil
    end
  end

  describe ".open" do
    it "opens the device by instance id" do
      with_virtual_gamepad do |gamepad|
        gamepad.name.should eq("Tryst Virtual Gamepad")
        gamepad.attached?.should be_true
        gamepad.instance_id.should eq(Tryst::SDL::Gamepad.virtual_id)
      end
    end

    it "raises for an unknown instance id" do
      expect_raises(Tryst::SDL::Error, /SDL_OpenGamepad/) do
        Tryst::SDL::Gamepad.open(999_999_u32)
      end
    end
  end

  describe ".first" do
    it "opens A gamepad when at least one is connected" do
      Tryst::SDL::Gamepad.attach_virtual
      begin
        gp = Tryst::SDL::Gamepad.first
        gp.should_not be_nil
        gp.try(&.destroy)
      ensure
        Tryst::SDL::Gamepad.detach_virtual
      end
    end
  end

  describe ".all" do
    it "includes the virtual device among whatever else is connected" do
      id = Tryst::SDL::Gamepad.attach_virtual
      begin
        all = Tryst::SDL::Gamepad.all
        all.map(&.instance_id).should contain(id)
        all.each(&.destroy)
      ensure
        Tryst::SDL::Gamepad.detach_virtual
      end
    end
  end

  describe "#button? / #axis" do
    it "starts at rest" do
      with_virtual_gamepad do |gamepad|
        Tryst::SDL::Gamepad::BUTTONS.each { |button| gamepad.button?(button).should be_false }
        Tryst::SDL::Gamepad::AXES.each { |axis| gamepad.axis(axis).should eq(0) }
      end
    end

    it "reflects a virtual button set, once .update_state has run" do
      with_virtual_gamepad do |gamepad|
        gamepad.set_virtual_button(:a, true)
        Tryst::SDL::Gamepad.update_state
        gamepad.button?(:a).should be_true
        gamepad.button?(:b).should be_false
      end
    end

    it "reflects a virtual axis set, once .update_state has run" do
      with_virtual_gamepad do |gamepad|
        gamepad.set_virtual_axis(:left_x, 12_345)
        Tryst::SDL::Gamepad.update_state
        gamepad.axis(:left_x).should eq(12_345)
      end
    end

    it "raises for an unknown button or axis symbol" do
      with_virtual_gamepad do |gamepad|
        expect_raises(ArgumentError, /unknown button/) { gamepad.button?(:nonexistent) }
        expect_raises(ArgumentError, /unknown axis/) { gamepad.axis(:nonexistent) }
      end
    end
  end

  describe "#rumble" do
    it "reports whether the device supports it, without raising" do
      with_virtual_gamepad do |gamepad|
        gamepad.rumble(1_000, 1_000, 50).should be_a(Bool)
      end
    end
  end

  describe "#guid" do
    it "is a 32-character hex string" do
      with_virtual_gamepad do |gamepad|
        gamepad.guid.should match(/\A[0-9a-f]{32}\z/)
      end
    end
  end

  describe "#destroy" do
    it "is idempotent and makes further use an error" do
      id = Tryst::SDL::Gamepad.attach_virtual
      begin
        gp = Tryst::SDL::Gamepad.open(id)
        gp.destroy
        gp.destroy
        gp.destroyed?.should be_true
        expect_raises(Tryst::SDL::Error, /closed/) { gp.name }
        expect_raises(Tryst::SDL::Error, /closed/) { gp.set_virtual_button(:a, true) }
      ensure
        Tryst::SDL::Gamepad.detach_virtual
      end
    end
  end

  describe ".poll_events" do
    it "dispatches button, axis and device-added events to registered blocks" do
      seen = [] of String
      Tryst::SDL::Gamepad.on_button { |instance_id, button, pressed| seen << "button #{instance_id} #{button} #{pressed}" }
      Tryst::SDL::Gamepad.on_axis { |instance_id, axis, value| seen << "axis #{instance_id} #{axis} #{value}" }
      Tryst::SDL::Gamepad.on_added { |instance_id| seen << "added #{instance_id}" }

      id = Tryst::SDL::Gamepad.attach_virtual
      begin
        gp = Tryst::SDL::Gamepad.open(id)
        gp.set_virtual_button(:a, true)
        gp.set_virtual_axis(:left_x, 999)

        Tryst::SDL::Gamepad.poll_events.should be > 0
        seen.should contain("added #{id}")
        seen.should contain("button #{id} a true")
        seen.should contain("axis #{id} left_x 999")

        gp.destroy
      ensure
        Tryst::SDL::Gamepad.detach_virtual
        # .detach_virtual queues a REMOVED event of its own - drained
        # here so it does not surface in whatever spec runs next.
        Tryst::SDL::Gamepad.poll_events
      end
    end

    it "dispatches a removed event on detach" do
      seen = [] of String
      Tryst::SDL::Gamepad.on_removed { |instance_id| seen << "removed #{instance_id}" }

      id = Tryst::SDL::Gamepad.attach_virtual
      gp = Tryst::SDL::Gamepad.open(id)
      gp.destroy
      Tryst::SDL::Gamepad.detach_virtual

      Tryst::SDL::Gamepad.poll_events
      seen.should contain("removed #{id}")
    end
  end

  describe ".update_state" do
    it "does not raise when the subsystem was never brought up" do
      Tryst::SDL::Gamepad.shutdown_subsystem
      Tryst::SDL::Gamepad.update_state
    end
  end
end
