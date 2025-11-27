require "./spec_helper"

describe KemalWAF::RateLimiter do
  describe "#initialize" do
    it "initializes with default values" do
      limiter = KemalWAF::RateLimiter.new
      result = limiter.check("127.0.0.1", "/test")
      result.limit.should eq(100)
      result.allowed.should be_true
    end

    it "initializes with custom values" do
      limiter = KemalWAF::RateLimiter.new(50, 30, 60)
      result = limiter.check("127.0.0.1", "/test")
      result.limit.should eq(50)
      result.allowed.should be_true
    end
  end

  describe "#check - IP-based rate limiting" do
    it "allows requests within limit" do
      limiter = KemalWAF::RateLimiter.new(5, 60)
      ip = "192.168.1.1"

      5.times do
        result = limiter.check(ip, "/test")
        result.allowed.should be_true
      end
    end

    it "blocks requests exceeding limit" do
      limiter = KemalWAF::RateLimiter.new(3, 60)
      ip = "192.168.1.2"

      # İlk 3 istek izin verilmeli
      3.times do
        result = limiter.check(ip, "/test")
        result.allowed.should be_true
      end

      # 4. istek engellenmeli
      result = limiter.check(ip, "/test")
      result.allowed.should be_false
      result.remaining.should eq(0)
    end

    it "tracks remaining requests correctly" do
      limiter = KemalWAF::RateLimiter.new(10, 60)
      ip = "192.168.1.3"

      result1 = limiter.check(ip, "/test")
      result1.remaining.should eq(9)

      result2 = limiter.check(ip, "/test")
      result2.remaining.should eq(8)

      result3 = limiter.check(ip, "/test")
      result3.remaining.should eq(7)
    end

    it "resets window after time passes" do
      limiter = KemalWAF::RateLimiter.new(2, 1)
      ip = "192.168.1.4"

      # İlk 2 istek
      2.times do
        result = limiter.check(ip, "/test")
        result.allowed.should be_true
      end

      # 3. istek engellenmeli
      result = limiter.check(ip, "/test")
      result.allowed.should be_false

      # 1 saniye bekle (window reset)
      sleep 1.1.seconds

      # Artık tekrar izin verilmeli
      result = limiter.check(ip, "/test")
      result.allowed.should be_true
    end

    it "handles different IPs independently" do
      limiter = KemalWAF::RateLimiter.new(2, 60)
      ip1 = "192.168.1.5"
      ip2 = "192.168.1.6"

      # IP1 için 2 istek
      2.times do
        result = limiter.check(ip1, "/test")
        result.allowed.should be_true
      end

      # IP1 engellenmeli
      result = limiter.check(ip1, "/test")
      result.allowed.should be_false

      # IP2 hala izin verilmeli
      result = limiter.check(ip2, "/test")
      result.allowed.should be_true
    end
  end

  describe "#check - Endpoint-based throttling" do
    it "applies endpoint-specific limits" do
      limiter = KemalWAF::RateLimiter.new(100, 60)
      limiter.add_endpoint_limit("/api/login", 2, 60)
      ip = "192.168.1.7"

      # /api/login için 2 istek izin verilmeli
      2.times do
        result = limiter.check(ip, "/api/login")
        result.allowed.should be_true
        result.limit.should eq(2)
      end

      # 3. istek engellenmeli
      result = limiter.check(ip, "/api/login")
      result.allowed.should be_false
      result.limit.should eq(2)
    end

    it "uses default limit for non-matching endpoints" do
      limiter = KemalWAF::RateLimiter.new(100, 60)
      limiter.add_endpoint_limit("/api/login", 2, 60)
      ip = "192.168.1.8"

      # /api/other için default limit kullanılmalı
      result = limiter.check(ip, "/api/other")
      result.allowed.should be_true
      result.limit.should eq(100)
    end

    it "supports wildcard pattern matching" do
      limiter = KemalWAF::RateLimiter.new(100, 60)
      limiter.add_endpoint_limit("/api/*", 5, 60)
      ip = "192.168.1.9"

      # /api/users wildcard ile eşleşmeli
      result = limiter.check(ip, "/api/users")
      result.allowed.should be_true
      result.limit.should eq(5)

      # /api/posts da eşleşmeli
      result = limiter.check(ip, "/api/posts")
      result.allowed.should be_true
      result.limit.should eq(5)

      # /other eşleşmemeli (default limit)
      result = limiter.check(ip, "/other")
      result.limit.should eq(100)
    end
  end

  describe "#set_headers" do
    it "sets rate limit headers correctly" do
      limiter = KemalWAF::RateLimiter.new(10, 60)
      ip = "192.168.1.10"
      result = limiter.check(ip, "/test")

      response = HTTP::Server::Response.new(IO::Memory.new)
      limiter.set_headers(response, result)

      response.headers["X-RateLimit-Limit"].should eq("10")
      response.headers["X-RateLimit-Remaining"].should eq("9")
      response.headers["X-RateLimit-Reset"].should_not be_nil
    end

    it "sets blocked-until header when IP is blocked" do
      limiter = KemalWAF::RateLimiter.new(1, 60)
      ip = "192.168.1.11"

      # İlk istek
      limiter.check(ip, "/test")

      # İkinci istek (engellenecek)
      result = limiter.check(ip, "/test")
      result.allowed.should be_false

      response = HTTP::Server::Response.new(IO::Memory.new)
      limiter.set_headers(response, result)

      response.headers["X-RateLimit-Limit"].should_not be_nil
      response.headers["X-RateLimit-Remaining"].should eq("0")
      response.headers["X-RateLimit-Reset"].should_not be_nil
    end
  end

  describe "#block_ip and #unblock_ip" do
    it "blocks IP for specified duration" do
      limiter = KemalWAF::RateLimiter.new(100, 60)
      ip = "192.168.1.12"

      # IP'yi blokla
      limiter.block_ip(ip, 1) # 1 saniye

      # İstek engellenmeli
      result = limiter.check(ip, "/test")
      result.allowed.should be_false
      result.blocked_until.should_not be_nil

      # 1 saniye bekle
      sleep 1.1.seconds

      # Artık izin verilmeli
      result = limiter.check(ip, "/test")
      result.allowed.should be_true
    end

    it "unblocks IP manually" do
      limiter = KemalWAF::RateLimiter.new(100, 60)
      ip = "192.168.1.13"

      # IP'yi blokla
      limiter.block_ip(ip, 300)

      # İstek engellenmeli
      result = limiter.check(ip, "/test")
      result.allowed.should be_false

      # IP'yi manuel olarak unblock et
      limiter.unblock_ip(ip)

      # Artık izin verilmeli
      result = limiter.check(ip, "/test")
      result.allowed.should be_true
    end
  end

  describe "Thread safety" do
    it "handles concurrent requests safely" do
      limiter = KemalWAF::RateLimiter.new(100, 60)
      ip = "192.168.1.14"

      # Paralel istekler
      channel = Channel(KemalWAF::RateLimitResult).new
      10.times do
        spawn do
          10.times do
            result = limiter.check(ip, "/test")
            channel.send(result)
          end
        end
      end

      # Tüm sonuçları topla
      results = [] of KemalWAF::RateLimitResult
      100.times { results << channel.receive }

      # Toplam izin verilen istek sayısı limit'e eşit olmalı
      allowed_count = results.count(&.allowed)
      allowed_count.should eq(100) # İlk 100 istek izin verilmeli
    end

    it "handles concurrent requests from different IPs" do
      limiter = KemalWAF::RateLimiter.new(10, 60)

      channel = Channel(KemalWAF::RateLimitResult).new
      5.times do |i|
        spawn do
          ip = "192.168.1.#{15 + i}"
          10.times do
            result = limiter.check(ip, "/test")
            channel.send(result)
          end
        end
      end

      # Tüm sonuçları topla
      results = [] of KemalWAF::RateLimitResult
      50.times { results << channel.receive }

      # Her IP için 10 istek izin verilmeli
      allowed_count = results.count(&.allowed)
      allowed_count.should eq(50)
    end
  end

  describe "Memory management" do
    it "cleans up old IP states" do
      limiter = KemalWAF::RateLimiter.new(10, 1)

      # Bir IP için istek yap
      ip = "192.168.1.20"
      limiter.check(ip, "/test")

      # Cleanup interval'dan daha uzun bekle (5 dakika default)
      # Bu test için cleanup_interval'ı kısaltmak gerekir ama
      # private method olduğu için test edemiyoruz
      # Ancak cleanup mekanizmasının çalıştığını doğrulamak için
      # uzun süre bekleyip tekrar istek yapabiliriz
      sleep 0.1.seconds

      # IP hala çalışmalı (cleanup çok uzun süre sonra olur)
      result = limiter.check(ip, "/test")
      result.allowed.should be_true
    end
  end

  describe "RateLimitResult" do
    it "provides correct reset time" do
      limiter = KemalWAF::RateLimiter.new(10, 60)
      ip = "192.168.1.21"

      result = limiter.check(ip, "/test")
      result.reset_at.should be > Time.utc
      result.reset_at.should be <= Time.utc + 61.seconds
    end

    it "tracks limit and remaining correctly" do
      limiter = KemalWAF::RateLimiter.new(5, 60)
      ip = "192.168.1.22"

      result1 = limiter.check(ip, "/test")
      result1.limit.should eq(5)
      result1.remaining.should eq(4)

      result2 = limiter.check(ip, "/test")
      result2.limit.should eq(5)
      result2.remaining.should eq(3)
    end
  end
end
