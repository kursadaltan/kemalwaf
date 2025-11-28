require "http/client"
require "uri"
require "openssl"
require "./connection_pool_manager"

module KemalWAF
  # Constants
  DEFAULT_RETRY_BACKOFF_MS    = 50
  DEFAULT_READ_TIMEOUT_SEC    = 30
  DEFAULT_CONNECT_TIMEOUT_SEC = 10

  # Upstream proxy client
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
        parsed_uri = URI.parse(upstream_url)
        raise "Invalid upstream URL" unless parsed_uri.host
        @default_upstream_uri = parsed_uri
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
                             raise "Invalid X-Next-Upstream URL" unless uri.host
                             Log.info { "Using X-Next-Upstream header: #{dynamic_upstream}" }
                             uri
                           rescue ex
                             Log.error { "X-Next-Upstream parse error: #{ex.message}, using default upstream" }
                             upstream_url ? URI.parse(upstream_url) : @default_upstream_uri
                           end
                         elsif upstream_url
                           URI.parse(upstream_url)
                         else
                           @default_upstream_uri
                         end

          raise "Upstream URI could not be determined" unless upstream_uri

          # Host header ve preserve ayarlarını belirle
          effective_custom_host_header = custom_host_header || @default_custom_host_header
          effective_preserve_original_host = preserve_original_host.nil? ? @default_preserve_original_host : preserve_original_host
          effective_verify_ssl = verify_ssl.nil? ? true : verify_ssl

          # Upstream bağlantısı oluştur
          tls_context = nil
          if upstream_uri.scheme == "https" && !effective_verify_ssl
            tls_context = OpenSSL::SSL::Context::Client.new
            tls_context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
            Log.debug { "SSL certificate verification disabled: #{upstream_uri}" }
          end

          # Get NEW connection for each retry (from pool or create new)
          # Don't use connection from previous attempt
          pool = @pool_manager.try(&.get_pool(upstream_uri, tls_context, effective_verify_ssl))
          client = if pool
                     pool.acquire || create_fallback_client(upstream_uri, tls_context)
                   else
                     create_fallback_client(upstream_uri, tls_context)
                   end

          raise "Connection could not be created" unless client
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
            Log.debug { "Preserving original Host header: #{original_host}" }
          elsif effective_custom_host_header
            headers["Host"] = effective_custom_host_header
            Log.debug { "Using custom Host header: #{effective_custom_host_header}" }
          elsif upstream_host = upstream_uri.host
            host_value = upstream_host
            host_value = "#{host_value}:#{upstream_uri.port}" if upstream_uri.port
            headers["Host"] = host_value
            Log.debug { "Host taken from upstream URI: #{host_value}" }
          end

          # İstek yolunu oluştur
          path = request.path
          if query = request.query
            path = "#{path}?#{query}"
          end

          Log.info { "Forwarding to upstream (attempt #{attempt + 1}/#{@max_retries}): #{request.method} #{upstream_uri}#{path}" }

          # İsteği upstream'e gönder
          response = client.exec(
            method: request.method,
            path: path,
            headers: headers,
            body: body
          )

          Log.info { "Upstream response: #{response.status_code}" }

          # Success - return connection to pool
          if pool && client
            pool.release(client)
          end

          return response
        rescue ex
          last_exception = ex
          Log.warn { "Upstream error (attempt #{attempt + 1}/#{@max_retries}): #{ex.message}" }

          # On error, DO NOT return connection to pool, CLOSE it
          # Because this connection may be faulty
          if client
            begin
              client.close
            rescue
              # Ignore close errors
            end
          end

          # If not last attempt, wait briefly and retry
          if attempt < @max_retries - 1
            sleep_time = DEFAULT_RETRY_BACKOFF_MS.milliseconds * (attempt + 1) # Exponential backoff-like
            Log.debug { "Waiting #{sleep_time.total_milliseconds}ms before retry..." }
            sleep sleep_time
          end
        ensure
          # Safety net: If connection was acquired but failed and not yet closed
          # (already closed in rescue above, this is just for safety to prevent leaks)
          # Only close if we're not using a pool (pool manages its own connections)
          if connection_acquired && client && !pool
            begin
              client.close
            rescue
              # Ignore close errors in ensure block
            end
          end
        end
      end

      # All retries failed
      Log.error { "All retry attempts failed (#{@max_retries} attempts)" }
      HTTP::Client::Response.new(
        status_code: 502,
        body: {error: "Upstream connection error", detail: last_exception.try(&.message) || "Unknown error", retries: @max_retries}.to_json,
        headers: HTTP::Headers{"Content-Type" => "application/json"}
      )
    end

    # Fallback: Create new connection (if pool disabled or cannot get from pool)
    private def create_fallback_client(upstream_uri : URI, tls_context : OpenSSL::SSL::Context::Client?) : HTTP::Client?
      begin
        client = HTTP::Client.new(upstream_uri, tls: tls_context)
        client.read_timeout = DEFAULT_READ_TIMEOUT_SEC.seconds
        client.connect_timeout = DEFAULT_CONNECT_TIMEOUT_SEC.seconds
        client
      rescue ex
        Log.error { "Failed to create fallback connection: #{ex.message}" }
        nil
      end
    end
  end
end
