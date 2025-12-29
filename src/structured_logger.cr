require "json"
require "uuid"
require "./log_rotator"
require "./rate_limiter"

module KemalWAF
  # JSON structured logging için log mesajı
  alias LogMessage = String

  # Structured logger - asenkron JSON logging
  class StructuredLogger
    Log = ::Log.for("structured_logger")

    @log_dir : String
    @base_name : String
    @log_rotator : LogRotator
    @queue : Channel(LogMessage)
    @batch_size : Int32
    @flush_interval_ms : Int32
    @running : Atomic(Int32)
    @current_file_path : String
    @file_mutex : Mutex
    @domain_loggers : Hash(String, LogRotator) = {} of String => LogRotator
    @domain_file_paths : Hash(String, String) = {} of String => String
    @domain_mutexes : Hash(String, Mutex) = {} of String => Mutex
    @domain_mutex : Mutex = Mutex.new

    def initialize(
      @log_dir : String,
      @base_name : String,
      max_size_mb : Int32,
      retention_days : Int32,
      queue_size : Int32 = 10000,
      @batch_size : Int32 = 100,
      @flush_interval_ms : Int32 = 1000,
    )
      @log_rotator = LogRotator.new(@log_dir, max_size_mb, retention_days)
      @queue = Channel(LogMessage).new(queue_size)
      @running = Atomic(Int32).new(1)
      @file_mutex = Mutex.new
      @current_file_path = @log_rotator.get_current_log_file(@base_name)

      # Background writer fiber'ı başlat
      spawn writer_loop

      Log.info { "StructuredLogger started: #{@log_dir}/#{@base_name}" }
    end

    # Request loglama (non-blocking)
    def log_request(
      request : HTTP::Request,
      result : EvaluationResult,
      duration : Time::Span,
      request_id : String? = nil,
      start_time : Time? = nil,
      domain : String? = nil,
    )
      request_id ||= UUID.random.to_s
      client_ip = extract_client_ip(request)

      log_entry = {
        timestamp:    (start_time || Time.utc).to_rfc3339,
        event_type:   "waf_request",
        request_id:   request_id,
        client_ip:    client_ip,
        method:       request.method,
        path:         request.path,
        query:        request.query || "",
        user_agent:   request.headers["User-Agent"]? || "",
        blocked:      result.blocked,
        observed:     result.observed,
        rule_id:      result.rule_id,
        rule_message: result.message,
        duration_ms:  duration.total_milliseconds,
        status_code:  result.blocked ? 403 : 200,
        domain:       domain,
      }.to_json

      enqueue(log_entry)
    end

    # Rule match loglama (non-blocking)
    def log_rule_match(rule : Rule, variable : String, value : String, request_id : String? = nil)
      # Privacy için value'yu truncate et
      truncated_value = value.size > 100 ? value[0..100] + "..." : value

      log_entry = {
        timestamp:     Time.utc.to_rfc3339,
        event_type:    "rule_match",
        request_id:    request_id || "",
        rule_id:       rule.id,
        rule_msg:      rule.msg,
        variable:      variable,
        matched_value: truncated_value,
        pattern:       rule.pattern,
      }.to_json

      enqueue(log_entry)
    end

    # Rate limit loglama (non-blocking)
    def log_rate_limit(
      request : HTTP::Request,
      result : RateLimitResult,
      request_id : String? = nil,
      start_time : Time? = nil,
      domain : String? = nil,
    )
      request_id ||= UUID.random.to_s
      client_ip = extract_client_ip(request)

      log_entry = {
        timestamp:     (start_time || Time.utc).to_rfc3339,
        event_type:    "rate_limit_exceeded",
        request_id:    request_id,
        client_ip:     client_ip,
        method:        request.method,
        path:          request.path,
        limit:         result.limit,
        remaining:     result.remaining,
        reset_at:      result.reset_at.to_rfc3339,
        blocked_until: result.blocked_until.try(&.to_rfc3339),
        domain:        domain,
      }.to_json

      enqueue(log_entry)
    end

    # Error loglama (non-blocking)
    def log_error(error : Exception, context : Hash(String, String) = {} of String => String)
      log_entry = {
        timestamp:  Time.utc.to_rfc3339,
        event_type: "error",
        error:      error.class.name,
        message:    error.message || "",
        backtrace:  error.backtrace?.try(&.[0..10]) || [] of String,
        context:    context,
      }.to_json

      enqueue(log_entry)
    end

    # Queue'ya log ekle (non-blocking, overflow durumunda drop)
    private def enqueue(message : LogMessage)
      return unless @running.get == 1

      # Non-blocking send - drop if queue full
      select
      when @queue.send(message)
        # Successfully added
      else
        # Queue full, log loss (optional: we can log here)
        Log.warn { "Log queue full, message lost" }
      end
    end

    # Background writer loop
    private def writer_loop
      batch = [] of LogMessage
      last_flush = Time.monotonic

      loop do
        break unless @running.get == 1

        # Batch size veya timeout kontrolü
        timeout = @flush_interval_ms.milliseconds
        should_flush = false

        select
        when message = @queue.receive
          batch << message
          should_flush = batch.size >= @batch_size
        when timeout(timeout)
          should_flush = !batch.empty?
        end

        if should_flush
          flush_batch(batch)
          batch.clear
          last_flush = Time.monotonic
        end
      end

      # Kapanırken kalan batch'i yaz
      flush_batch(batch) unless batch.empty?
    end

    # Batch'i dosyaya yaz
    private def flush_batch(batch : Array(LogMessage))
      return if batch.empty?

      # Domain bazlı batch'leri ayır
      domain_batches = {} of String => Array(LogMessage)
      global_batch = [] of LogMessage

      batch.each do |message|
        begin
          parsed = JSON.parse(message)
          domain = parsed["domain"]?.try(&.as_s?)

          if domain && !domain.empty?
            sanitized = sanitize_domain_name(domain)
            domain_batches[sanitized] ||= [] of LogMessage
            domain_batches[sanitized] << message
          else
            global_batch << message
          end
        rescue
          # Parse hatası durumunda global batch'e ekle
          global_batch << message
        end
      end

      # Global log dosyasına yaz
      unless global_batch.empty?
        @file_mutex.synchronize do
          flush_to_file(@base_name, @current_file_path, @log_rotator, global_batch)
        end
      end

      # Domain bazlı log dosyalarına yaz
      domain_batches.each do |sanitized_domain, domain_messages|
        flush_domain_batch(sanitized_domain, domain_messages)
      end
    end

    # Domain bazlı batch'i dosyaya yaz
    private def flush_domain_batch(sanitized_domain : String, messages : Array(LogMessage))
      @domain_mutex.synchronize do
        # Domain için LogRotator ve file path'i al veya oluştur
        log_rotator = @domain_loggers[sanitized_domain]?
        unless log_rotator
          log_rotator = LogRotator.new(@log_dir, @log_rotator.max_size_mb, @log_rotator.retention_days)
          @domain_loggers[sanitized_domain] = log_rotator
        end

        file_path = @domain_file_paths[sanitized_domain]?
        unless file_path
          file_path = log_rotator.get_current_log_file("waf-#{sanitized_domain}")
          @domain_file_paths[sanitized_domain] = file_path
        end

        mutex = @domain_mutexes[sanitized_domain]?
        unless mutex
          mutex = Mutex.new
          @domain_mutexes[sanitized_domain] = mutex
        end

        mutex.synchronize do
          flush_to_file("waf-#{sanitized_domain}", file_path, log_rotator, messages)
          @domain_file_paths[sanitized_domain] = file_path
        end
      end
    end

    # Dosyaya yazma işlemi (ortak metod)
    private def flush_to_file(base_name : String, file_path : String, log_rotator : LogRotator, messages : Array(LogMessage))
      begin
        # Rotation kontrolü
        current_date = Time.local
        if log_rotator.should_rotate?(file_path, current_date)
          log_rotator.rotate_log_file(file_path, current_date)
          file_path = log_rotator.get_current_log_file(base_name, current_date)
        end

        # Dosyaya yaz
        File.open(file_path, "a") do |file|
          messages.each do |message|
            file.puts(message)
          end
        end
      rescue ex
        Log.error { "Log write error: #{ex.message}" }
      end
    end

    # Domain adını sanitize et (dosya adı için güvenli hale getir)
    private def sanitize_domain_name(domain : String) : String
      domain.gsub(/[^a-zA-Z0-9\-]/, "-").downcase
    end

    # Client IP extraction
    private def extract_client_ip(request : HTTP::Request) : String
      # X-Forwarded-For header'ından IP al
      if forwarded_for = request.headers["X-Forwarded-For"]?
        # İlk IP'yi al (proxy chain'de ilk gerçek IP)
        forwarded_for.split(',')[0].strip
      elsif real_ip = request.headers["X-Real-IP"]?
        real_ip.strip
      else
        # Remote address (Kemal context'ten alınabilir)
        "unknown"
      end
    end

    # Graceful shutdown - queue'daki tüm log'ları yaz
    def shutdown
      @running.set(0)
      @queue.close

      # Kalan mesajları yaz
      remaining = [] of LogMessage
      loop do
        select
        when message = @queue.receive?
          remaining << message if message
        else
          break
        end
      end

      flush_batch(remaining) unless remaining.empty?
      Log.info { "StructuredLogger shut down" }
    end
  end
end
