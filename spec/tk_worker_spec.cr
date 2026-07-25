require "./spec_helper"
require "./support/tk_worker_client"

# Tests TkWorkerClient itself - the persistent-worker/reuse/shutdown
# properties, as opposed to spec/support/tk_cases.cr's tk_test examples,
# which exercise the actual Tk-facing behavior through the same client.
describe TkWorkerClient do
  it "reuses the same persistent worker process across multiple calls" do
    TkWorkerClient.stop # clean slate regardless of example order

    result1 = TkWorkerClient.run("eval and invoke marshaling round trip")
    result1.success?.should be_true
    pid_after_first = TkWorkerClient.pid

    result2 = TkWorkerClient.run("widget creation and button invoke fires a registered callback")
    result2.success?.should be_true
    TkWorkerClient.pid.should eq(pid_after_first)
  end

  it "reports a clean failure for an unknown test name" do
    result = TkWorkerClient.run("this test does not exist")
    result.success?.should be_false
  end

  it "can be stopped and lazily respawns on the next call" do
    TkWorkerClient.run("eval and invoke marshaling round trip")
    pid_before = TkWorkerClient.pid
    TkWorkerClient.stop
    TkWorkerClient.running?.should be_false

    TkWorkerClient.run("eval and invoke marshaling round trip").success?.should be_true
    TkWorkerClient.pid.should_not eq(pid_before)
  end
end
