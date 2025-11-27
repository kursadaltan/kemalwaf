require "http/server"
require "json"

# Mock upstream server for integration tests
class TestUpstreamServer
  @server : HTTP::Server?
  @port : Int32

  def initialize(@port : Int32 = 8080)
  end

  def start
    @server = HTTP::Server.new do |context|
      context.response.content_type = "application/json"
      context.response.status_code = 200

      body_content = context.request.body.try(&.gets_to_end) || ""

      # Path ve query'yi birleştir
      full_path = context.request.path
      if query = context.request.query
        full_path = "#{full_path}?#{query}"
      end

      # Headers'ı normalize et
      headers_hash = {} of String => String
      context.request.headers.each do |key, values|
        headers_hash[key.downcase] = values.first
      end

      body = {
        method:  context.request.method,
        path:    full_path,
        headers: headers_hash,
        body:    body_content,
      }.to_json

      context.response.print(body)
    end

    # Port çakışmasını önlemek için farklı port dene
    begin
      spawn { @server.not_nil!.listen("0.0.0.0", @port) }
      sleep 2.seconds # Server'ın başlaması için bekle

      # Server'ın gerçekten başladığını kontrol et
      retries = 0
      while retries < 5
        begin
          client = HTTP::Client.new(URI.parse("http://localhost:#{@port}"))
          client.read_timeout = 1.second
          client.get("/")
          client.close
          break
        rescue
          retries += 1
          sleep 0.5.seconds
        end
      end
    rescue ex
      # Port kullanımda ise farklı bir port dene
      @port = 8888
      spawn { @server.not_nil!.listen("0.0.0.0", @port) }
      sleep 2.seconds
    end
  end

  def stop
    @server.try(&.close) if @server
  end

  def url : String
    "http://localhost:#{@port}"
  end
end
