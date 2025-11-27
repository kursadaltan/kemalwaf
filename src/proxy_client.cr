require "http/client"
require "uri"
require "openssl"
require "./connection_pool_manager"

module KemalWAF
  # Upstream proxy istemcisi
  class ProxyClient
    Log = ::Log.for("proxy_client")

    @default_upstream_uri : URI?
    @default_custom_host_header : String?
    @default_preserve_original_host : Bool
    @pool_manager : ConnectionPoolManager?
    @max_retries : Int32

    def initialize(
      upstream_url : String? = nil,
      custom_host_header : String = "",
      preserve_original_host : Bool = false,
      pool_manager : ConnectionPoolManager? = nil,
      max_retries : Int32 = 3,
    )
      if upstream_url
        @default_upstream_uri = URI.parse(upstream_url)
        raise "Geçersiz upstream URL" unless @default_upstream_uri.not_nil!.host
      else
        @default_upstream_uri = nil
      end
      @default_custom_host_header = custom_host_header.empty? ? nil : custom_host_header
      @default_preserve_original_host = preserve_original_host
      @pool_manager = pool_manager
      @max_retries = max_retries
    end

    # Dinamik upstream ile forward
    def forward(request : HTTP::Request, body : String?, upstream_url : String? = nil, custom_host_header : String? = nil, preserve_original_host : Bool? = nil, verify_ssl : Bool? = nil) : HTTP::Client::Response
      # Retry mekanizması ile isteği gönder
      last_exception : Exception? = nil

      @max_retries.times do |attempt|
        pool : ConnectionPool? = nil
        client : HTTP::Client? = nil
        connection_acquired = false

        begin
          # X-Next-Upstream header'ını kontrol et
          dynamic_upstream = request.headers["X-Next-Upstream"]?

          # Upstream URI'yi belirle: X-Next-Upstream > parametre > default
          upstream_uri = if dynamic_upstream
                           begin
                             uri = URI.parse(dynamic_upstream)
                             raise "Geçersiz X-Next-Upstream URL" unless uri.host
                             Log.info { "X-Next-Upstream header kullanılıyor: #{dynamic_upstream}" }
                             uri
                           rescue ex
                             Log.error { "X-Next-Upstream parse hatası: #{ex.message}, default upstream kullanılıyor" }
                             upstream_url ? URI.parse(upstream_url) : @default_upstream_uri
                           end
                         elsif upstream_url
                           URI.parse(upstream_url)
                         else
                           @default_upstream_uri
                         end

          raise "Upstream URI belirlenemedi" unless upstream_uri

          # Host header ve preserve ayarlarını belirle
          effective_custom_host_header = custom_host_header || @default_custom_host_header
          effective_preserve_original_host = preserve_original_host.nil? ? @default_preserve_original_host : preserve_original_host
          effective_verify_ssl = verify_ssl.nil? ? true : verify_ssl

          # Upstream bağlantısı oluştur
          tls_context = nil
          if upstream_uri.scheme == "https" && !effective_verify_ssl
            tls_context = OpenSSL::SSL::Context::Client.new
            tls_context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
            Log.debug { "SSL sertifika doğrulaması devre dışı bırakıldı: #{upstream_uri}" }
          end

          # Her retry'da YENİ connection al (pool'dan veya yeni oluştur)
          # Önceki attempt'taki connection'ı kullanma
          pool = @pool_manager.try(&.get_pool(upstream_uri, tls_context, effective_verify_ssl))
          client = if pool
                     pool.not_nil!.acquire || create_fallback_client(upstream_uri, tls_context)
                   else
                     create_fallback_client(upstream_uri, tls_context)
                   end

          raise "Connection oluşturulamadı" unless client
          connection_acquired = true

          # İstek başlıklarını kopyala
          headers = HTTP::Headers.new
          original_host = nil

          request.headers.each do |key, values|
            key_lower = key.downcase

            if key_lower == "host"
              original_host = values.first?
              next if effective_preserve_original_host
            end

            next if key_lower == "accept-encoding"
            next if key_lower == "connection"
            next if key_lower == "keep-alive"

            values.each do |value|
              headers.add(key, value)
            end
          end

          # Host başlığını ayarla
          if effective_preserve_original_host && original_host
            headers["Host"] = original_host
            Log.debug { "Orijinal Host header korunuyor: #{original_host}" }
          elsif effective_custom_host_header
            headers["Host"] = effective_custom_host_header.not_nil!
            Log.debug { "Özel Host header kullanılıyor: #{effective_custom_host_header}" }
          elsif upstream_uri.host
            host_value = upstream_uri.host.not_nil!
            host_value = "#{host_value}:#{upstream_uri.port}" if upstream_uri.port
            headers["Host"] = host_value
            Log.debug { "Upstream URI'den Host alındı: #{host_value}" }
          end

          # İstek yolunu oluştur
          path = request.path
          if query = request.query
            path = "#{path}?#{query}"
          end

          Log.info { "Upstream'e yönlendiriliyor (attempt #{attempt + 1}/#{@max_retries}): #{request.method} #{upstream_uri}#{path}" }

          # İsteği upstream'e gönder
          response = client.exec(
            method: request.method,
            path: path,
            headers: headers,
            body: body
          )

          Log.info { "Upstream yanıtı: #{response.status_code}" }

          # Başarılı - connection'ı pool'a geri ver
          if pool && client
            pool.release(client)
          end

          return response
        rescue ex
          last_exception = ex
          Log.warn { "Upstream hatası (attempt #{attempt + 1}/#{@max_retries}): #{ex.message}" }

          # Hata durumunda connection'ı pool'a GERİ VERME, KAPAT
          # Çünkü bu connection hatalı olabilir
          if client
            begin
              client.close
            rescue
              # Ignore close errors
            end
          end

          # Son attempt değilse, kısa bir bekleme yap ve tekrar dene
          if attempt < @max_retries - 1
            sleep_time = 50.milliseconds * (attempt + 1) # Exponential backoff benzeri
            Log.debug { "Retry için #{sleep_time.total_milliseconds}ms bekleniyor..." }
            sleep sleep_time
          end
        ensure
          # Eğer connection alındı ama başarısız olduysa ve henüz kapatılmadıysa
          # (yukarıdaki rescue'da zaten kapatıldı, bu sadece güvenlik için)
          if connection_acquired && client && !pool
            begin
              client.close
            rescue
            end
          end
        end
      end

      # Tüm retry'lar başarısız oldu
      Log.error { "Tüm retry denemeleri başarısız oldu (#{@max_retries} attempt)" }
      HTTP::Client::Response.new(
        status_code: 502,
        body: {error: "Upstream bağlantı hatası", detail: last_exception.try(&.message) || "Unknown error", retries: @max_retries}.to_json,
        headers: HTTP::Headers{"Content-Type" => "application/json"}
      )
    end

    # Fallback: Yeni connection oluştur (pool disabled veya pool'dan alınamazsa)
    private def create_fallback_client(upstream_uri : URI, tls_context : OpenSSL::SSL::Context::Client?) : HTTP::Client?
      begin
        client = HTTP::Client.new(upstream_uri, tls: tls_context)
        client.read_timeout = 30.seconds
        client.connect_timeout = 10.seconds
        client
      rescue ex
        Log.error { "Fallback connection oluşturulamadı: #{ex.message}" }
        nil
      end
    end
  end
end
