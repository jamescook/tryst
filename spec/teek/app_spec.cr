require "../spec_helper"

# See spec/standalone/app_core_fixture.cr for why this runs as a subprocess
# rather than constructing Teek::App directly in this spec.
describe Teek::App do
  it "bootstraps and delegates tcl_eval/tcl_invoke/destroy/callbacks/update correctly" do
    process = Process.new(
      "crystal", ["run", "spec/standalone/app_core_fixture.cr"],
      output: Process::Redirect::Pipe,
      error: Process::Redirect::Pipe,
    )
    output = process.output.gets_to_end
    error = process.error.gets_to_end
    status = process.wait

    fail("app_core_fixture failed:\nstdout: #{output}\nstderr: #{error}") unless status.success?
    output.chomp.should eq("OK")
  end
end
