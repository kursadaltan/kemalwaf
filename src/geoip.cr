require "process"

module KemalWAF
  # GeoIP lookup sonucu
  struct GeoIPResult
    property country_code : String?
    property country_name : String?
    property city : String?
    property latitude : Float64?
    property longitude : Float64?
    property isp : String?
    property organization : String?

    def initialize(
      @country_code = nil,
      @country_name = nil,
      @city = nil,
      @latitude = nil,
      @longitude = nil,
      @isp = nil,
      @organization = nil,
    )
    end
  end

  # GeoIP Filter - MaxMind GeoIP2 entegrasyonu
  class GeoIPFilter
    Log = ::Log.for("geoip")

    @blocked_countries : Set(String)
    @allowed_countries : Set(String)
    @enabled : Bool
    @mutex : Mutex
    @cache : Hash(String, Tuple(GeoIPResult?, Time))
    @cache_ttl : Time::Span
    @mmdb_file_path : String?

    def initialize(
      enabled : Bool = false,
      blocked_countries : Array(String) = [] of String,
      allowed_countries : Array(String) = [] of String,
      cache_ttl : Time::Span = 1.hour,
    )
      @enabled = enabled
      @blocked_countries = Set(String).new(blocked_countries.map(&.upcase))
      @allowed_countries = Set(String).new(allowed_countries.map(&.upcase))
      @cache_ttl = cache_ttl
      @mutex = Mutex.new
      @cache = Hash(String, Tuple(GeoIPResult?, Time)).new
      @mmdb_file_path = ENV["GEOIP_MMDB_FILE"]?

      # MMDB dosyası kontrolü
      if mmdb_path = @mmdb_file_path
        unless File.exists?(mmdb_path)
          Log.warn { "MMDB dosyası bulunamadı: #{mmdb_path}" }
          @mmdb_file_path = nil
        else
          # mmdblookup aracının yüklü olup olmadığını kontrol et
          begin
            output = IO::Memory.new
            error = IO::Memory.new
            status = Process.run("mmdblookup", ["--version"], output: output, error: error)
            if status.success?
              Log.info { "MMDB dosyası yüklendi: #{mmdb_path}" }
            else
              Log.warn { "mmdblookup aracı bulunamadı. GeoIP çalışmayacak. Yüklemek için: brew install libmaxminddb" }
              @mmdb_file_path = nil
            end
          rescue
            Log.warn { "mmdblookup aracı bulunamadı. GeoIP çalışmayacak. Yüklemek için: brew install libmaxminddb" }
            @mmdb_file_path = nil
          end
        end
      end

      # Cache cleanup fiber'ı başlat
      spawn cache_cleanup_loop if @enabled
    end

    # IP'nin engellenip engellenmediğini kontrol et
    def blocked?(ip : String) : Tuple(Bool, String?)
      return {false, nil} unless @enabled

      result = lookup(ip)
      return {false, nil} unless result

      country_code = result.country_code
      return {false, nil} unless country_code

      country_code_up = country_code.upcase

      # Allowed countries kontrolü (öncelikli)
      if !@allowed_countries.empty?
        if @allowed_countries.includes?(country_code_up)
          return {false, nil}
        else
          return {true, "Country #{country_code} (#{result.country_name}) not in allowed list"}
        end
      end

      # Blocked countries kontrolü
      if @blocked_countries.includes?(country_code_up)
        return {true, "Country #{country_code} (#{result.country_name}) is blocked"}
      end

      {false, nil}
    end

    # IP için GeoIP lookup yap
    def lookup(ip : String) : GeoIPResult?
      return nil unless @enabled

      # Cache kontrolü
      @mutex.synchronize do
        if cached = @cache[ip]?
          result, cached_time = cached
          if Time.utc - cached_time < @cache_ttl
            return result
          else
            @cache.delete(ip)
          end
        end
      end

      # Lookup yap
      result = perform_lookup(ip)

      # Cache'e ekle
      @mutex.synchronize do
        @cache[ip] = {result, Time.utc}
      end

      result
    rescue ex
      Log.error { "GeoIP lookup hatası: #{ex.message}" }
      nil
    end

    # Ülke kodunu al
    def country(ip : String) : String?
      lookup(ip).try(&.country_code)
    end

    # Blocked countries listesine ekle
    def add_blocked_country(country_code : String)
      @mutex.synchronize do
        @blocked_countries.add(country_code.upcase)
        Log.info { "Blocked country eklendi: #{country_code.upcase}" }
      end
    end

    # Allowed countries listesine ekle
    def add_allowed_country(country_code : String)
      @mutex.synchronize do
        @allowed_countries.add(country_code.upcase)
        Log.info { "Allowed country eklendi: #{country_code.upcase}" }
      end
    end

    # Blocked countries listesinden kaldır
    def remove_blocked_country(country_code : String)
      @mutex.synchronize do
        @blocked_countries.delete(country_code.upcase)
        Log.info { "Blocked country kaldırıldı: #{country_code.upcase}" }
      end
    end

    # Allowed countries listesinden kaldır
    def remove_allowed_country(country_code : String)
      @mutex.synchronize do
        @allowed_countries.delete(country_code.upcase)
        Log.info { "Allowed country kaldırıldı: #{country_code.upcase}" }
      end
    end

    # İstatistikler
    def stats : Hash(String, Int32)
      @mutex.synchronize do
        {
          "blocked_countries" => @blocked_countries.size,
          "allowed_countries" => @allowed_countries.size,
          "cache_size"        => @cache.size,
        }
      end
    end

    # Cache'i temizle
    def clear_cache
      @mutex.synchronize do
        @cache.clear
        Log.info { "GeoIP cache temizlendi" }
      end
    end

    private def perform_lookup(ip : String) : GeoIPResult?
      # Sadece MMDB dosyası kullanılıyor
      return nil unless @mmdb_file_path

      lookup_mmdb(ip)
    end

    private def lookup_mmdb(ip : String) : GeoIPResult?
      return nil unless @mmdb_file_path

      # mmdblookup komut satırı aracını kullan
      # mmdblookup --file GeoLite2-Country.mmdb --ip 1.2.3.4 country iso_code
      begin
        # Ülke kodu al
        output = IO::Memory.new
        error = IO::Memory.new
        status = Process.run(
          "mmdblookup",
          ["--file", @mmdb_file_path.not_nil!, "--ip", ip, "country", "iso_code"],
          output: output,
          error: error
        )

        return nil unless status.success?

        country_code = output.to_s.strip
        return nil if country_code.empty? || country_code == "<data>"

        # Ülke adı al (opsiyonel)
        output_name = IO::Memory.new
        error_name = IO::Memory.new
        status_name = Process.run(
          "mmdblookup",
          ["--file", @mmdb_file_path.not_nil!, "--ip", ip, "country", "names", "en"],
          output: output_name,
          error: error_name
        )

        country_name = nil
        if status_name.success?
          country_name = output_name.to_s.strip
          country_name = nil if country_name.empty? || country_name == "<data>"
        end

        GeoIPResult.new(
          country_code: country_code,
          country_name: country_name
        )
      rescue ex
        Log.warn { "MMDB lookup hatası: #{ex.message}" }
        nil
      end
    end

    private def cache_cleanup_loop
      loop do
        sleep 1.hour
        cleanup_expired_cache
      end
    end

    private def cleanup_expired_cache
      now = Time.utc
      @mutex.synchronize do
        expired_keys = [] of String
        @cache.each do |ip, cached|
          result, cached_time = cached
          if now - cached_time >= @cache_ttl
            expired_keys << ip
          end
        end
        expired_keys.each { |ip| @cache.delete(ip) }
        Log.debug { "GeoIP cache temizlendi: #{expired_keys.size} entry kaldırıldı" } if expired_keys.size > 0
      end
    end
  end
end
