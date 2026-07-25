require "json"

# JSON-line message shapes shared between spec/support/tk_worker.cr
# (server side) and spec/support/tk_worker_client.cr (runner side), so
# the two can't drift apart.
module TkWorker
  struct Request
    include JSON::Serializable
    property cmd : String
    property name : String?

    def initialize(@cmd : String, @name : String? = nil)
    end
  end

  struct Response
    include JSON::Serializable
    property? success : Bool
    property error : String?

    def initialize(@success : Bool, @error : String? = nil)
    end
  end
end
