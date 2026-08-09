require "../../src/teek/ui"

# Standalone verification for Teek::UI::Session#realize's atomicity on
# error - see session_realize_fixture.cr for why this needs its own
# subprocess.

session = Teek::UI.app(title: "session realize error fixture") do |builder|
  builder.button(:first, text: "Ok")
  builder.document.root.add_child(Teek::UI::Node.new(type: :not_a_real_widget_type, name: :bad))
end

begin
  session.realize
  raise "expected #realize to raise for an unregistered node type"
rescue Teek::UI::NotRealizedError
  raise "expected #realize's own ArgumentError, not NotRealizedError to propagate here"
rescue ArgumentError
  # expected - the tree includes a node type with no registered WidgetType
end

begin
  session.app
  raise "expected #app to still raise NotRealizedError - the session must be left exactly as if #realize had never been called"
rescue Teek::UI::NotRealizedError
  # expected
end

puts "OK"
