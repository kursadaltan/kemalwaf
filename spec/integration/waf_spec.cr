require "../spec_helper"
require "./test_server"
require "http/client"
require "json"
require "uri"

describe "WAF Integration" do
  # Test için geçici kural dizini oluştur
  test_rules_dir = "spec/fixtures/rules"
  test_upstream = TestUpstreamServer.new(8080)
  waf_process = nil

  before_all do
    # Test upstream server'ı başlat
    # Not: CI'da test upstream server zaten başlatılmış olabilir
    # Bu durumda sadece kontrol et, başlatılmamışsa başlat
    begin
      client = HTTP::Client.new(URI.parse("http://localhost:8080"))
      client.read_timeout = 1.second
      client.get("/")
      client.close
      # Upstream server zaten çalışıyor (CI'da başlatılmış)
    rescue
      # Upstream server çalışmıyor, başlat
      test_upstream.start
      sleep 1.second
    end
  end

  after_all do
    test_upstream.stop
    waf_process.try(&.terminate)
  end

  describe "malicious request blocking" do
    it "blocks SQL injection in query parameters" do
      client = HTTP::Client.new(URI.parse("http://localhost:3000"))
      # Query parametresini URL encode et
      uri = URI.parse("http://localhost:3000/?id=union%20select")
      response = client.get(uri.path + "?" + uri.query.not_nil!)
      # Eğer WAF çalışıyorsa 403 dönmeli
      response.status_code.should eq(403)
    end

    it "blocks XSS attacks" do
      client = HTTP::Client.new(URI.parse("http://localhost:3000"))
      response = client.get("/?q=<script>alert('xss')</script>")
      response.status_code.should eq(403)
    end

    it "blocks SQL injection in POST body" do
      client = HTTP::Client.new(URI.parse("http://localhost:3000"))
      response = client.post("/api/login", body: "username=union select")
      response.status_code.should eq(403)
    end
  end

  describe "clean request allowing" do
    it "allows normal GET requests" do
      client = HTTP::Client.new(URI.parse("http://localhost:3000"))
      response = client.get("/test?id=123")
      # Clean request'ler upstream'e yönlendirilmeli
      response.status_code.should eq(200)
    end

    it "allows normal POST requests" do
      client = HTTP::Client.new(URI.parse("http://localhost:3000"))
      response = client.post("/api/data", body: %({"key": "value"}))
      response.status_code.should eq(200)
    end
  end

  describe "observe mode" do
    pending "logs but does not block in observe mode" do
      # Observe mode için OBSERVE=true environment variable gerekir
      # Bu test için WAF'ın observe mode'da başlatılması gerekir
      # Şimdilik pending - WAF observe mode'da başlatılmadıysa test atlanır
      client = HTTP::Client.new(URI.parse("http://localhost:3000"))
      response = client.get("/?id=union select")
      # Observe mode'da istek engellenmemeli ama loglanmalı
      response.status_code.should be < 400
    end
  end

  describe "metrics endpoint" do
    it "returns Prometheus metrics" do
      client = HTTP::Client.new(URI.parse("http://localhost:3000"))
      response = client.get("/metrics")
      response.status_code.should eq(200)
      response.headers["Content-Type"].should contain("text/plain")
      response.body.should contain("waf_requests_total")
      response.body.should contain("waf_blocked_total")
      response.body.should contain("waf_observed_total")
      response.body.should contain("waf_rules_loaded")
    end
  end

  describe "health endpoint" do
    it "returns health status" do
      client = HTTP::Client.new(URI.parse("http://localhost:3000"))
      response = client.get("/health")
      response.status_code.should eq(200)
      response.headers["Content-Type"].should contain("application/json")

      body = JSON.parse(response.body)
      body["status"].as_s.should eq("healthy")
      body["rules_loaded"].as_i.should be >= 0
      body.as_h.has_key?("observe_mode").should be_true
    end
  end

  describe "403 response format" do
    it "returns proper 403 HTML response" do
      client = HTTP::Client.new(URI.parse("http://localhost:3000"))
      # Query parametresini URL encode et
      uri = URI.parse("http://localhost:3000/?id=union%20select")
      response = client.get(uri.path + "?" + uri.query.not_nil!)
      response.status_code.should eq(403)
      response.headers["Content-Type"].should contain("text/html")
      response.body.should contain("403")
      response.body.should contain("blocked")
    end
  end

  describe "upstream proxy forwarding" do
    it "forwards allowed requests to upstream" do
      client = HTTP::Client.new(URI.parse("http://localhost:3000"))
      response = client.get("/test")
      # Clean request upstream'e yönlendirilmeli
      response.status_code.should eq(200)

      # Upstream response kontrolü
      body = JSON.parse(response.body)
      body["path"].as_s.should eq("/test")
    end

    it "preserves request method" do
      client = HTTP::Client.new(URI.parse("http://localhost:3000"))
      response = client.post("/api/test", body: %({"test": "data"}))
      response.status_code.should eq(200)

      body = JSON.parse(response.body)
      body["method"].as_s.should eq("POST")
    end

    it "preserves request headers" do
      client = HTTP::Client.new(URI.parse("http://localhost:3000"))
      headers = HTTP::Headers{"X-Custom-Header" => "test-value"}
      response = client.get("/test", headers: headers)
      response.status_code.should eq(200)

      body = JSON.parse(response.body)
      headers_hash = body["headers"].as_h
      # Headers key'leri lowercase olabilir
      headers_hash.has_key?("x-custom-header").should be_true
    end
  end
end
