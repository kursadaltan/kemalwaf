require "./spec_helper"
require "../src/ip_filter"

describe KemalWAF::IPFilter do
  describe "#initialize" do
    it "initializes with enabled state" do
      filter = KemalWAF::IPFilter.new(true)
      result = filter.allowed?("127.0.0.1")
      result.allowed.should be_true
      result.source.should eq("default")
    end

    it "initializes with disabled state" do
      filter = KemalWAF::IPFilter.new(false)
      result = filter.allowed?("127.0.0.1")
      result.allowed.should be_true
      result.reason.should eq("IP filtering disabled")
    end
  end

  describe "#allowed? - Whitelist" do
    it "allows IPs in whitelist" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_whitelist_ip("192.168.1.100")

      result = filter.allowed?("192.168.1.100")
      result.allowed.should be_true
      result.source.should eq("whitelist")
      result.reason.should contain("whitelist")
    end

    it "allows IPs in whitelist CIDR" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_whitelist_cidr("192.168.1.0/24")

      result = filter.allowed?("192.168.1.50")
      result.allowed.should be_true
      result.source.should eq("whitelist")
      result.reason.should contain("CIDR")
    end

    it "whitelist takes priority over blacklist" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_whitelist_ip("192.168.1.100")
      filter.add_blacklist_ip("192.168.1.100")

      result = filter.allowed?("192.168.1.100")
      result.allowed.should be_true
      result.source.should eq("whitelist")
    end
  end

  describe "#allowed? - Blacklist" do
    it "blocks IPs in blacklist" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_blacklist_ip("10.0.0.100")

      result = filter.allowed?("10.0.0.100")
      result.allowed.should be_false
      result.source.should eq("blacklist")
      result.reason.should contain("blacklist")
    end

    it "blocks IPs in blacklist CIDR" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_blacklist_cidr("10.0.0.0/24")

      result = filter.allowed?("10.0.0.50")
      result.allowed.should be_false
      result.source.should eq("blacklist")
      result.reason.should contain("CIDR")
    end

    it "allows IPs not in blacklist" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_blacklist_ip("10.0.0.100")

      result = filter.allowed?("10.0.0.200")
      result.allowed.should be_true
      result.source.should eq("default")
    end
  end

  describe "#allowed? - Priority order" do
    it "checks whitelist before blacklist" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_whitelist_ip("192.168.1.100")
      filter.add_blacklist_cidr("192.168.1.0/24")

      # Whitelist'teki IP, blacklist CIDR'de olsa bile izin verilmeli
      result = filter.allowed?("192.168.1.100")
      result.allowed.should be_true
      result.source.should eq("whitelist")
    end

    it "allows default IPs when not in any list" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_blacklist_ip("10.0.0.100")

      result = filter.allowed?("172.16.0.1")
      result.allowed.should be_true
      result.source.should eq("default")
    end
  end

  describe "CIDR Network" do
    it "validates IPv4 CIDR format" do
      filter = KemalWAF::IPFilter.new(true)

      # Geçersiz formatlar için hata fırlatılmalı
      # Ancak add_whitelist_cidr hataları yakalıyor, bu yüzden direkt CIDRNetwork.new kullanmalıyız
      expect_raises(ArgumentError) do
        KemalWAF::CIDRNetwork.new("invalid")
      end

      expect_raises(ArgumentError) do
        KemalWAF::CIDRNetwork.new("192.168.1.0")
      end
    end

    it "handles IPv4 CIDR correctly" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_whitelist_cidr("192.168.1.0/24")

      # Network içindeki IP'ler
      result1 = filter.allowed?("192.168.1.1")
      result1.allowed.should be_true
      result1.source.should eq("whitelist")

      result2 = filter.allowed?("192.168.1.255")
      result2.allowed.should be_true
      result2.source.should eq("whitelist")

      # Network dışındaki IP'ler (whitelist'te değil, default olarak izin verilir)
      result3 = filter.allowed?("192.168.2.1")
      result3.allowed.should be_true
      result3.source.should eq("default")
    end

    it "handles /32 CIDR (single IP)" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_blacklist_cidr("10.0.0.1/32")

      result1 = filter.allowed?("10.0.0.1")
      result1.allowed.should be_false

      result2 = filter.allowed?("10.0.0.2")
      result2.allowed.should be_true
    end

    it "handles /16 CIDR (large subnet)" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_blacklist_cidr("10.0.0.0/16")

      result1 = filter.allowed?("10.0.1.1")
      result1.allowed.should be_false

      result2 = filter.allowed?("10.1.0.1")
      result2.allowed.should be_true
    end
  end

  describe "#add_whitelist_ip and #add_blacklist_ip" do
    it "adds single IPs correctly" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_whitelist_ip("192.168.1.100")
      filter.add_blacklist_ip("10.0.0.100")

      result1 = filter.allowed?("192.168.1.100")
      result1.allowed.should be_true

      result2 = filter.allowed?("10.0.0.100")
      result2.allowed.should be_false
    end

    it "handles whitespace in IP addresses" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_whitelist_ip("  192.168.1.100  ")

      result = filter.allowed?("192.168.1.100")
      result.allowed.should be_true
    end
  end

  describe "#remove_whitelist_ip and #remove_blacklist_ip" do
    it "removes IPs from whitelist" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_whitelist_ip("192.168.1.100")

      result1 = filter.allowed?("192.168.1.100")
      result1.allowed.should be_true

      filter.remove_whitelist_ip("192.168.1.100")

      result2 = filter.allowed?("192.168.1.100")
      result2.source.should eq("default")
    end

    it "removes IPs from blacklist" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_blacklist_ip("10.0.0.100")

      result1 = filter.allowed?("10.0.0.100")
      result1.allowed.should be_false

      filter.remove_blacklist_ip("10.0.0.100")

      result2 = filter.allowed?("10.0.0.100")
      result2.allowed.should be_true
    end
  end

  describe "#load_from_file" do
    it "loads IPs from file" do
      # Geçici test dosyası oluştur
      test_file = File.tempfile("ip_list_test") do |file|
        file.puts("# Yorum satırı")
        file.puts("192.168.1.100")
        file.puts("")
        file.puts("10.0.0.100")
        file.puts("192.168.2.0/24")
      end

      filter = KemalWAF::IPFilter.new(true)
      filter.load_from_file(test_file.path, :whitelist)

      # Tek IP'ler
      result1 = filter.allowed?("192.168.1.100")
      result1.allowed.should be_true

      result2 = filter.allowed?("10.0.0.100")
      result2.allowed.should be_true

      # CIDR
      result3 = filter.allowed?("192.168.2.50")
      result3.allowed.should be_true

      # Dosyada olmayan IP
      result4 = filter.allowed?("172.16.0.1")
      result4.source.should eq("default")

      File.delete(test_file.path)
    end

    it "handles non-existent file gracefully" do
      filter = KemalWAF::IPFilter.new(true)

      # Hata fırlatmamalı
      filter.load_from_file("/nonexistent/file.txt", :whitelist)

      result = filter.allowed?("127.0.0.1")
      result.allowed.should be_true
    end

    it "loads blacklist from file" do
      test_file = File.tempfile("blacklist_test") do |file|
        file.puts("10.0.0.100")
        file.puts("10.0.1.0/24")
      end

      filter = KemalWAF::IPFilter.new(true)
      filter.load_from_file(test_file.path, :blacklist)

      result1 = filter.allowed?("10.0.0.100")
      result1.allowed.should be_false

      result2 = filter.allowed?("10.0.1.50")
      result2.allowed.should be_false

      File.delete(test_file.path)
    end

    it "ignores comment lines" do
      test_file = File.tempfile("comment_test") do |file|
        file.puts("# Bu bir yorum")
        file.puts("192.168.1.100")
        file.puts("  # Başka yorum")
        file.puts("10.0.0.100")
      end

      filter = KemalWAF::IPFilter.new(true)
      filter.load_from_file(test_file.path, :whitelist)

      result1 = filter.allowed?("192.168.1.100")
      result1.allowed.should be_true

      result2 = filter.allowed?("10.0.0.100")
      result2.allowed.should be_true

      File.delete(test_file.path)
    end

    it "ignores empty lines" do
      test_file = File.tempfile("empty_test") do |file|
        file.puts("")
        file.puts("192.168.1.100")
        file.puts("")
        file.puts("")
        file.puts("10.0.0.100")
      end

      filter = KemalWAF::IPFilter.new(true)
      filter.load_from_file(test_file.path, :whitelist)

      result1 = filter.allowed?("192.168.1.100")
      result1.allowed.should be_true

      result2 = filter.allowed?("10.0.0.100")
      result2.allowed.should be_true

      File.delete(test_file.path)
    end
  end

  describe "#stats" do
    it "returns correct statistics" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_whitelist_ip("192.168.1.100")
      filter.add_whitelist_ip("192.168.1.101")
      filter.add_blacklist_ip("10.0.0.100")
      filter.add_whitelist_cidr("192.168.2.0/24")
      filter.add_blacklist_cidr("10.0.1.0/24")

      stats = filter.stats
      stats["whitelist_ips"].should eq(2)
      stats["blacklist_ips"].should eq(1)
      stats["whitelist_cidrs"].should eq(1)
      stats["blacklist_cidrs"].should eq(1)
    end

    it "returns zero stats for empty filter" do
      filter = KemalWAF::IPFilter.new(true)
      stats = filter.stats

      stats["whitelist_ips"].should eq(0)
      stats["blacklist_ips"].should eq(0)
      stats["whitelist_cidrs"].should eq(0)
      stats["blacklist_cidrs"].should eq(0)
    end
  end

  describe "#clear" do
    it "clears all lists" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_whitelist_ip("192.168.1.100")
      filter.add_blacklist_ip("10.0.0.100")
      filter.add_whitelist_cidr("192.168.2.0/24")

      filter.clear

      stats = filter.stats
      stats["whitelist_ips"].should eq(0)
      stats["blacklist_ips"].should eq(0)
      stats["whitelist_cidrs"].should eq(0)
      stats["blacklist_cidrs"].should eq(0)

      result = filter.allowed?("192.168.1.100")
      result.source.should eq("default")
    end
  end

  describe "Thread safety" do
    it "handles concurrent access safely" do
      filter = KemalWAF::IPFilter.new(true)

      channel = Channel(Bool).new

      # Paralel olarak IP ekleme ve kontrol
      10.times do |i|
        spawn do
          ip = "192.168.1.#{i}"
          filter.add_whitelist_ip(ip)
          result = filter.allowed?(ip)
          channel.send(result.allowed)
        end
      end

      # Tüm sonuçları topla
      results = [] of Bool
      10.times { results << channel.receive }

      # Tüm IP'ler izin verilmeli
      results.all?(&.itself).should be_true
    end

    it "handles concurrent file loading" do
      test_file1 = File.tempfile("test1") do |file|
        file.puts("192.168.1.100")
      end
      test_file2 = File.tempfile("test2") do |file|
        file.puts("10.0.0.100")
      end

      filter = KemalWAF::IPFilter.new(true)

      channel = Channel(Nil).new

      spawn do
        filter.load_from_file(test_file1.path, :whitelist)
        channel.send(nil)
      end

      spawn do
        filter.load_from_file(test_file2.path, :blacklist)
        channel.send(nil)
      end

      # Her iki dosya da yüklensin
      2.times { channel.receive }

      result1 = filter.allowed?("192.168.1.100")
      result1.allowed.should be_true

      result2 = filter.allowed?("10.0.0.100")
      result2.allowed.should be_false

      File.delete(test_file1.path)
      File.delete(test_file2.path)
    end
  end

  describe "Edge cases" do
    it "handles invalid IP addresses gracefully" do
      filter = KemalWAF::IPFilter.new(true)

      # Geçersiz IP'ler için hata fırlatmamalı
      result1 = filter.allowed?("invalid-ip")
      result1.allowed.should be_true # Default olarak izin ver

      result2 = filter.allowed?("999.999.999.999")
      result2.allowed.should be_true
    end

    it "handles empty IP string" do
      filter = KemalWAF::IPFilter.new(true)
      result = filter.allowed?("")
      result.allowed.should be_true
    end

    it "handles IPv6 addresses" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_blacklist_ip("2001:db8::1")

      result = filter.allowed?("2001:db8::1")
      result.allowed.should be_false
    end

    it "handles mixed IPv4 and IPv6" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_whitelist_ip("192.168.1.100")
      filter.add_blacklist_ip("2001:db8::1")

      result1 = filter.allowed?("192.168.1.100")
      result1.allowed.should be_true

      result2 = filter.allowed?("2001:db8::1")
      result2.allowed.should be_false
    end
  end

  describe "IPFilterResult" do
    it "provides correct result structure" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_whitelist_ip("192.168.1.100")

      result = filter.allowed?("192.168.1.100")
      result.allowed.should be_true
      result.reason.should_not be_empty
      result.source.should eq("whitelist")
    end

    it "provides different sources for different lists" do
      filter = KemalWAF::IPFilter.new(true)
      filter.add_whitelist_ip("192.168.1.100")
      filter.add_blacklist_ip("10.0.0.100")

      result1 = filter.allowed?("192.168.1.100")
      result1.source.should eq("whitelist")

      result2 = filter.allowed?("10.0.0.100")
      result2.source.should eq("blacklist")

      result3 = filter.allowed?("172.16.0.1")
      result3.source.should eq("default")
    end
  end
end
