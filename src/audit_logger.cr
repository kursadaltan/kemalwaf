require "./log_rotator"

module KemalWAF
  # Audit log mesajı
  alias AuditLogMessage = String

  # Audit logger - kritik olaylar için ayrı log
  class AuditLogger
    Log = ::Log.for("audit_logger")

    @log_dir : String
    @base_name : String
    @log_rotator : LogRotator
    @queue : Channel(AuditLogMessage)
    @batch_size : Int32
    @flush_interval_ms : Int32
    @running : Atomic(Int32)
    @current_file_path : String
    @file_mutex : Mutex

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
      @queue = Channel(AuditLogMessage).new(queue_size)
      @running = Atomic(Int32).new(1)
      @file_mutex = Mutex.new
      @current_file_path = @log_rotator.get_current_log_file(@base_name)

      # Background writer fiber'ı başlat
      spawn writer_loop

      Log.info { "AuditLogger started: #{@log_dir}/#{@base_name}" }
    end

    # Block edilen istek loglama (non-blocking)
    def log_block(
      request : HTTP::Request,
      rule : Rule,
      result : EvaluationResult,
      request_id : String? = nil,
    )
      client_ip = extract_client_ip(request)
      timestamp = Time.utc.to_rfc3339

      log_entry = "#{timestamp} | BLOCK | IP:#{client_ip} | RULE:#{rule.id} | PATH:#{request.path} | METHOD:#{request.method} | REASON:#{result.message || rule.msg}"

      enqueue(log_entry)
    end

    # Konfigürasyon değişikliği loglama (non-blocking)
    def log_config_change(action : String, details : String, user : String? = nil)
      timestamp = Time.utc.to_rfc3339
      user_part = user ? " | USER:#{user}" : ""

      log_entry = "#{timestamp} | CONFIG_CHANGE | ACTION:#{action}#{user_part} | DETAILS:#{details}"

      enqueue(log_entry)
    end

    # Güvenlik olayı loglama (non-blocking)
    def log_security_event(event_type : String, details : String, request_id : String? = nil)
      timestamp = Time.utc.to_rfc3339
      request_part = request_id ? " | REQUEST_ID:#{request_id}" : ""

      log_entry = "#{timestamp} | SECURITY_EVENT | TYPE:#{event_type}#{request_part} | DETAILS:#{details}"

      enqueue(log_entry)
    end

    # Queue'ya log ekle (non-blocking, overflow durumunda drop)
    private def enqueue(message : AuditLogMessage)
      return unless @running.get == 1

      # Non-blocking send - drop if queue full
      select
      when @queue.send(message)
        # Successfully added
      else
        # Queue full, log loss
        Log.warn { "Audit log queue full, message lost" }
      end
    end

    # Background writer loop
    private def writer_loop
      batch = [] of AuditLogMessage
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
    private def flush_batch(batch : Array(AuditLogMessage))
      return if batch.empty?

      @file_mutex.synchronize do
        begin
          # Rotation kontrolü
          current_date = Time.local
          if @log_rotator.should_rotate?(@current_file_path, current_date)
            @log_rotator.rotate_log_file(@current_file_path, current_date)
            @current_file_path = @log_rotator.get_current_log_file(@base_name, current_date)
          end

          # Dosyaya yaz
          File.open(@current_file_path, "a") do |file|
            batch.each do |message|
              file.puts(message)
            end
          end
        rescue ex
          Log.error { "Audit log write error: #{ex.message}" }
        end
      end
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
        "unknown"
      end
    end

    # Graceful shutdown - queue'daki tüm log'ları yaz
    def shutdown
      @running.set(0)
      @queue.close

      # Kalan mesajları yaz
      remaining = [] of AuditLogMessage
      loop do
        select
        when message = @queue.receive?
          remaining << message if message
        else
          break
        end
      end

      flush_batch(remaining) unless remaining.empty?
      Log.info { "AuditLogger shut down" }
    end
  end
end
