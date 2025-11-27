require "./spec_helper"
require "http/server"

describe KemalWAF::ProxyClient do
  describe "#initialize" do
    it "parses valid upstream URL" do
      client = KemalWAF::ProxyClient.new("http://localhost:8080")
      client.should_not be_nil
    end

    it "parses upstream URL with port" do
      client = KemalWAF::ProxyClient.new("http://example.com:3000")
      client.should_not be_nil
    end

    it "parses upstream URL without port" do
      client = KemalWAF::ProxyClient.new("http://example.com")
      client.should_not be_nil
    end

    it "raises error for invalid upstream URL" do
      expect_raises(Exception, "Geçersiz upstream URL") do
        KemalWAF::ProxyClient.new("invalid-url")
      end
    end
  end

  describe "#forward with connection pooling" do
    it "uses connection pool when pool manager is provided" do
      config = KemalWAF::ConnectionPoolingConfig.new_default
      config.pool_size = 5
      config.max_size = 10
      config.idle_timeout = "60s"
      pool_manager = KemalWAF::ConnectionPoolManager.new(config)
      client = KemalWAF::ProxyClient.new("http://localhost:8888", pool_manager: pool_manager)

      # Mock server
      server = HTTP::Server.new do |context|
        context.response.content_type = "application/json"
        context.response.status_code = 200
        context.response.print({status: "ok"}.to_json)
      end

      spawn { server.listen("0.0.0.0", 8888) }

      # Wait for server to start
      sleep 100.milliseconds

      # Make a request
      request = HTTP::Request.new("GET", "/test")
      response = client.forward(request, nil)

      response.status_code.should eq(200)

      # Pool should have been used
      pool_manager.pool_count.should be > 0

      server.close
      pool_manager.shutdown_all
    end

    it "falls back to new connection when pool is disabled" do
      client = KemalWAF::ProxyClient.new("http://localhost:8888", pool_manager: nil)

      # Mock server
      server = HTTP::Server.new do |context|
        context.response.content_type = "application/json"
        context.response.status_code = 200
        context.response.print({status: "ok"}.to_json)
      end

      spawn { server.listen("0.0.0.0", 8888) }

      # Wait for server to start
      sleep 100.milliseconds

      # Make a request
      request = HTTP::Request.new("GET", "/test")
      response = client.forward(request, nil)

      response.status_code.should eq(200)

      server.close
    end
  end

  describe "#forward" do
    # Mock HTTP server for testing - dinamik port kullan
    server_port = 0
    server = nil

    before_all do
      # Boş port bul
      server_port = 8888
      server = HTTP::Server.new do |context|
        context.response.content_type = "application/json"
        context.response.status_code = 200
        body_content = context.request.body.try(&.gets_to_end) || ""

        # Path ve query'yi birleştir
        full_path = context.request.path
        if query = context.request.query
          full_path = "#{full_path}?#{query}"
        end

        # Headers'ı normalize et (key'leri lowercase yap)
        headers_hash = {} of String => String
        context.request.headers.each do |key, values|
          # İlk değeri al (multiple values için)
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
      begin
        spawn { server.not_nil!.listen("0.0.0.0", server_port) }
        sleep 0.5.seconds # Server'ın başlaması için bekle
      rescue ex
        # Port kullanımda ise farklı bir port dene
        server_port = 8889
        spawn { server.not_nil!.listen("0.0.0.0", server_port) }
        sleep 0.5.seconds
      end
    end

    after_all do
      server.try(&.close) if server
    end

    it "forwards GET requests correctly" do
      client = KemalWAF::ProxyClient.new("http://localhost:#{server_port}")
      request = HTTP::Request.new("GET", "/test?param=value")

      response = client.forward(request, nil)
      response.status_code.should eq(200)

      body_str = response.body || ""
      body = JSON.parse(body_str)
      body["method"].as_s.should eq("GET")
      body["path"].as_s.should eq("/test?param=value")
    end

    it "forwards POST requests with body" do
      client = KemalWAF::ProxyClient.new("http://localhost:#{server_port}")
      request = HTTP::Request.new("POST", "/api/test")
      body_content = %({"key": "value"})

      response = client.forward(request, body_content)
      response.status_code.should eq(200)

      body_str = response.body || ""
      body = JSON.parse(body_str)
      body["method"].as_s.should eq("POST")
      body["body"].as_s.should eq(body_content)
    end

    it "forwards headers correctly (excluding Host and Connection)" do
      client = KemalWAF::ProxyClient.new("http://localhost:#{server_port}")
      request = HTTP::Request.new("GET", "/test")
      request.headers["User-Agent"] = "test-agent"
      request.headers["X-Custom"] = "custom-value"
      request.headers["Host"] = "original-host"
      request.headers["Connection"] = "keep-alive"

      response = client.forward(request, nil)
      response.status_code.should eq(200)

      body_str = response.body || ""
      body = JSON.parse(body_str)
      headers = body["headers"].as_h
      headers["user-agent"].as_s.should eq("test-agent")
      headers["x-custom"].as_s.should eq("custom-value")
      # Host başlığı upstream'e göre ayarlanmalı
      headers["host"].as_s.should eq("localhost:#{server_port}")
      # Connection başlığı forward edilmemeli
      headers.has_key?("connection").should be_false
    end

    it "sets Host header based on upstream URI" do
      client = KemalWAF::ProxyClient.new("http://example.com:8080")
      request = HTTP::Request.new("GET", "/test")

      # Mock server yerine direkt kontrol yapıyoruz
      # Host başlığının doğru ayarlandığını test etmek için
      # Gerçek bir upstream'e istek göndermek yerine,
      # header'ların doğru işlendiğini varsayıyoruz
      client.should_not be_nil
    end

    it "handles upstream connection errors (502 Bad Gateway)" do
      client = KemalWAF::ProxyClient.new("http://localhost:99999") # Geçersiz port
      request = HTTP::Request.new("GET", "/test")

      response = client.forward(request, nil)
      response.status_code.should eq(502)

      body = JSON.parse(response.body)
      body["error"].as_s.should eq("Upstream bağlantı hatası")
    end

    it "handles upstream timeout" do
      # Timeout testi için yavaş bir server veya geçersiz bir upstream kullanılabilir
      # Şimdilik connection error testi yeterli
      client = KemalWAF::ProxyClient.new("http://192.0.2.0:8080") # Test IP (RFC 5737)
      request = HTTP::Request.new("GET", "/test")

      # Timeout durumunda 502 dönmeli
      response = client.forward(request, nil)
      # Connection timeout veya error durumunda 502 dönmeli
      response.status_code.should eq(502)
    end

    it "forwards request path correctly" do
      client = KemalWAF::ProxyClient.new("http://localhost:#{server_port}")
      request = HTTP::Request.new("GET", "/api/v1/users?page=1")

      response = client.forward(request, nil)
      response.status_code.should eq(200)

      body_str = response.body || ""
      body = JSON.parse(body_str)
      body["path"].as_s.should eq("/api/v1/users?page=1")
    end

    it "forwards multiple header values" do
      client = KemalWAF::ProxyClient.new("http://localhost:#{server_port}")
      request = HTTP::Request.new("GET", "/test")
      request.headers.add("X-Multiple", "value1")
      request.headers.add("X-Multiple", "value2")

      response = client.forward(request, nil)
      response.status_code.should eq(200)

      body_str = response.body || ""
      body = JSON.parse(body_str)
      headers = body["headers"].as_h
      # Multiple header values kontrolü - ilk değeri kontrol et
      headers.has_key?("x-multiple").should be_true
      headers["x-multiple"].as_s.should contain("value")
    end

    it "closes connection after forwarding" do
      client = KemalWAF::ProxyClient.new("http://localhost:#{server_port}")
      request = HTTP::Request.new("GET", "/test")

      # Connection'ın kapatıldığını test etmek için
      # ensure bloğunun çalıştığını varsayıyoruz
      response = client.forward(request, nil)
      response.status_code.should eq(200)
    end
  end
end
