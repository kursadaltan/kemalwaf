require "socket"

module KemalWAF
  # IP filter sonucu
  struct IPFilterResult
    property allowed : Bool
    property reason : String
    property source : String # "whitelist", "blacklist", "geoip", "default"

    def initialize(@allowed, @reason, @source)
    end
  end

  # CIDR network representation
  class CIDRNetwork
    property network_ip : String
    property prefix : Int32
    property is_ipv6 : Bool

    def initialize(cidr_string : String)
      # CIDR format: "192.168.1.0/24" veya "2001:db8::/32"
      parts = cidr_string.split('/')
      raise ArgumentError.new("Geçersiz CIDR formatı: #{cidr_string}") if parts.size != 2

      network_ip_str = parts[0].strip
      prefix_val = parts[1].to_i
      is_ipv6_val = network_ip_str.includes?(':')

      # IP formatını doğrula
      begin
        validate_ip(network_ip_str)
      rescue ex
        raise ArgumentError.new("Geçersiz CIDR: #{cidr_string} - #{ex.message}")
      end

      @network_ip = network_ip_str
      @prefix = prefix_val
      @is_ipv6 = is_ipv6_val
    end

    def includes?(ip_string : String) : Bool
      return false if @is_ipv6 != ip_string.includes?(':')

      begin
        validate_ip(ip_string)

        if @is_ipv6
          ipv6_in_cidr?(ip_string, @network_ip, @prefix)
        else
          ipv4_in_cidr?(ip_string, @network_ip, @prefix)
        end
      rescue
        false
      end
    end

    private def validate_ip(ip_string : String)
      if ip_string.includes?(':')
        # IPv6 için basit doğrulama
        Socket::IPAddress.parse("http://[#{ip_string}]:80")
      else
        # IPv4 için basit doğrulama
        Socket::IPAddress.parse("http://#{ip_string}:80")
      end
    end

    private def ipv4_in_cidr?(ip : String, network : String, prefix : Int32) : Bool
      ip_parts = ip.split('.').map(&.to_i)
      net_parts = network.split('.').map(&.to_i)

      # IP'yi 32-bit integer'a çevir
      ip_int = (ip_parts[0] << 24) | (ip_parts[1] << 16) | (ip_parts[2] << 8) | ip_parts[3]
      net_int = (net_parts[0] << 24) | (net_parts[1] << 16) | (net_parts[2] << 8) | net_parts[3]

      # Network mask
      mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF

      (ip_int & mask) == (net_int & mask)
    end

    private def ipv6_in_cidr?(ip : String, network : String, prefix : Int32) : Bool
      # IPv6 için basitleştirilmiş kontrol (tam implementasyon daha karmaşık)
      # Bu basit bir implementasyon, production için daha gelişmiş bir çözüm gerekebilir
      begin
        # IPv6 CIDR kontrolü için basit yaklaşım
        # Gerçek implementasyon için 128-bit işlemler gerekir
        # Şimdilik sadece exact match kontrol ediyoruz
        ip == network
      rescue
        false
      end
    end
  end

  # IP Filter - whitelist/blacklist ve CIDR desteği
  class IPFilter
    Log = ::Log.for("ip_filter")

    @whitelist : Set(String)
    @blacklist : Set(String)
    @cidr_whitelist : Array(CIDRNetwork)
    @cidr_blacklist : Array(CIDRNetwork)
    @mutex : Mutex
    @enabled : Bool

    def initialize(@enabled : Bool = true)
      @whitelist = Set(String).new
      @blacklist = Set(String).new
      @cidr_whitelist = [] of CIDRNetwork
      @cidr_blacklist = [] of CIDRNetwork
      @mutex = Mutex.new
    end

    # IP'nin izin verilip verilmediğini kontrol et
    def allowed?(ip : String) : IPFilterResult
      return IPFilterResult.new(true, "IP filtering disabled", "default") unless @enabled

      @mutex.synchronize do
        # 1. Whitelist kontrolü (öncelikli - eğer whitelist'teyse direkt izin ver)
        if @whitelist.includes?(ip)
          return IPFilterResult.new(true, "IP whitelist'te", "whitelist")
        end

        # CIDR whitelist kontrolü
        @cidr_whitelist.each do |cidr|
          if cidr.includes?(ip)
            return IPFilterResult.new(true, "IP whitelist CIDR'de (#{cidr.network_ip}/#{cidr.prefix})", "whitelist")
          end
        end

        # 2. Blacklist kontrolü
        if @blacklist.includes?(ip)
          return IPFilterResult.new(false, "IP blacklist'te", "blacklist")
        end

        # CIDR blacklist kontrolü
        @cidr_blacklist.each do |cidr|
          if cidr.includes?(ip)
            return IPFilterResult.new(false, "IP blacklist CIDR'de (#{cidr.network_ip}/#{cidr.prefix})", "blacklist")
          end
        end

        # 3. Varsayılan olarak izin ver
        IPFilterResult.new(true, "IP filtrelenmedi", "default")
      end
    end

    # Tek IP ekle (whitelist)
    def add_whitelist_ip(ip : String)
      @mutex.synchronize do
        @whitelist.add(ip.strip)
        Log.info { "Whitelist'e IP eklendi: #{ip}" }
      end
    end

    # Tek IP ekle (blacklist)
    def add_blacklist_ip(ip : String)
      @mutex.synchronize do
        @blacklist.add(ip.strip)
        Log.info { "Blacklist'e IP eklendi: #{ip}" }
      end
    end

    # CIDR network ekle (whitelist)
    def add_whitelist_cidr(cidr_string : String)
      @mutex.synchronize do
        cidr = CIDRNetwork.new(cidr_string)
        @cidr_whitelist << cidr
        Log.info { "Whitelist'e CIDR eklendi: #{cidr_string}" }
      end
    rescue ex
      Log.error { "CIDR eklenemedi: #{cidr_string} - #{ex.message}" }
    end

    # CIDR network ekle (blacklist)
    def add_blacklist_cidr(cidr_string : String)
      @mutex.synchronize do
        cidr = CIDRNetwork.new(cidr_string)
        @cidr_blacklist << cidr
        Log.info { "Blacklist'e CIDR eklendi: #{cidr_string}" }
      end
    rescue ex
      Log.error { "CIDR eklenemedi: #{cidr_string} - #{ex.message}" }
    end

    # Dosyadan IP listesi yükle
    def load_from_file(file_path : String, list_type : Symbol)
      return unless File.exists?(file_path)

      begin
        File.each_line(file_path) do |line|
          line = line.strip
          next if line.empty?
          next if line.starts_with?('#') # Yorum satırları

          # CIDR formatı kontrolü
          if line.includes?('/')
            case list_type
            when :whitelist
              add_whitelist_cidr(line)
            when :blacklist
              add_blacklist_cidr(line)
            end
          else
            # Tek IP
            case list_type
            when :whitelist
              add_whitelist_ip(line)
            when :blacklist
              add_blacklist_ip(line)
            end
          end
        end

        Log.info { "IP listesi yüklendi: #{file_path} (#{list_type})" }
      rescue ex
        Log.error { "IP listesi yüklenemedi: #{file_path} - #{ex.message}" }
      end
    end

    # IP'yi whitelist'ten kaldır
    def remove_whitelist_ip(ip : String)
      @mutex.synchronize do
        @whitelist.delete(ip.strip)
        Log.info { "Whitelist'ten IP kaldırıldı: #{ip}" }
      end
    end

    # IP'yi blacklist'ten kaldır
    def remove_blacklist_ip(ip : String)
      @mutex.synchronize do
        @blacklist.delete(ip.strip)
        Log.info { "Blacklist'ten IP kaldırıldı: #{ip}" }
      end
    end

    # İstatistikler
    def stats : Hash(String, Int32)
      @mutex.synchronize do
        {
          "whitelist_ips"   => @whitelist.size,
          "blacklist_ips"   => @blacklist.size,
          "whitelist_cidrs" => @cidr_whitelist.size,
          "blacklist_cidrs" => @cidr_blacklist.size,
        }
      end
    end

    # Tüm listeleri temizle
    def clear
      @mutex.synchronize do
        @whitelist.clear
        @blacklist.clear
        @cidr_whitelist.clear
        @cidr_blacklist.clear
        Log.info { "Tüm IP listeleri temizlendi" }
      end
    end
  end
end
