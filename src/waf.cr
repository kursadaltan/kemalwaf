require "kemal"
require "json"
require "ecr"
require "uuid"
require "./rule_loader"
require "./evaluator"
require "./proxy_client"
require "./metrics"
require "./structured_logger"
require "./audit_logger"
require "./log_rotator"
require "./rate_limiter"
require "./ip_filter"
require "./geoip"
require "./config_loader"
require "./connection_pool_manager"

def render_waf_403(rule_id : String?, message : String?, observe : Bool) : String
  logo = "https://avatars3.githubusercontent.com/u/15321198?v=3&s=200"
  rid = rule_id || "N/A"
  msg = message || "Suspicious request detected and blocked."
  mode = observe ? "observe" : "enforce"
  ray = Random::Secure.hex(16)
  timestamp = Time.utc.to_s("%Y-%m-%d %H:%M:%SZ")

  ECR.render("#{__DIR__}/views/403.ecr")
end

def render_waf_502(domain : String, upstream : String, message : String) : String
  logo = "https://avatars3.githubusercontent.com/u/15321198?v=3&s=200"
  msg = message
  ray = Random::Secure.hex(16)
  timestamp = Time.utc.to_s("%Y-%m-%d %H:%M:%SZ")

  ECR.render("#{__DIR__}/views/502.ecr")
end

def render_waf_429(limit : Int32, reset_at : Time, message : String) : String
  logo = "https://avatars3.githubusercontent.com/u/15321198?v=3&s=200"
  msg = message
  ray = Random::Secure.hex(16)
  timestamp = Time.utc.to_s("%Y-%m-%d %H:%M:%SZ")
  reset_at_str = reset_at.to_s("%Y-%m-%d %H:%M:%S UTC")

  ECR.render("#{__DIR__}/views/429.ecr")
end

module KemalWAF
  Log = ::Log.for("waf")

  # Konfigürasyon
  RULE_DIR               = ENV.fetch("RULE_DIR", "rules")
  UPSTREAM               = ENV.fetch("UPSTREAM", "http://localhost:8080")
  UPSTREAM_HOST_HEADER   = ENV.fetch("UPSTREAM_HOST_HEADER", "")                  # Boş ise upstream URI'den alınır, set edilirse bu kullanılır
  PRESERVE_ORIGINAL_HOST = ENV.fetch("PRESERVE_ORIGINAL_HOST", "false") == "true" # Orijinal request'teki Host header'ını koru
  OBSERVE_MODE           = ENV.fetch("OBSERVE", "false") == "true"
  BODY_LIMIT             = ENV.fetch("BODY_LIMIT_BYTES", "1048576").to_i
  RELOAD_INTERVAL        = ENV.fetch("RELOAD_INTERVAL_SEC", "5").to_i

  # Logging konfigürasyonu
  LOG_DIR                  = ENV.fetch("LOG_DIR", "logs")
  LOG_MAX_SIZE_MB          = ENV.fetch("LOG_MAX_SIZE_MB", "100").to_i
  LOG_RETENTION_DAYS       = ENV.fetch("LOG_RETENTION_DAYS", "30").to_i
  AUDIT_LOG_MAX_SIZE_MB    = ENV.fetch("AUDIT_LOG_MAX_SIZE_MB", "50").to_i
  AUDIT_LOG_RETENTION_DAYS = ENV.fetch("AUDIT_LOG_RETENTION_DAYS", "90").to_i
  LOG_ENABLE_AUDIT         = ENV.fetch("LOG_ENABLE_AUDIT", "true") == "true"
  LOG_QUEUE_SIZE           = ENV.fetch("LOG_QUEUE_SIZE", "10000").to_i
  LOG_BATCH_SIZE           = ENV.fetch("LOG_BATCH_SIZE", "100").to_i
  LOG_FLUSH_INTERVAL_MS    = ENV.fetch("LOG_FLUSH_INTERVAL_MS", "1000").to_i

  # Rate limiting konfigürasyonu
  RATE_LIMIT_ENABLED            = ENV.fetch("RATE_LIMIT_ENABLED", "true") == "true"
  RATE_LIMIT_DEFAULT            = ENV.fetch("RATE_LIMIT_DEFAULT", "100000").to_i
  RATE_LIMIT_WINDOW_SEC         = ENV.fetch("RATE_LIMIT_WINDOW_SEC", "60").to_i
  RATE_LIMIT_BLOCK_DURATION_SEC = ENV.fetch("RATE_LIMIT_BLOCK_DURATION_SEC", "300").to_i

  # IP filtering konfigürasyonu
  IP_FILTER_ENABLED = ENV.fetch("IP_FILTER_ENABLED", "true") == "true"
  IP_WHITELIST_FILE = ENV.fetch("IP_WHITELIST_FILE", "")
  IP_BLACKLIST_FILE = ENV.fetch("IP_BLACKLIST_FILE", "")

  # GeoIP filtering konfigürasyonu
  GEOIP_ENABLED           = ENV.fetch("GEOIP_ENABLED", "false") == "true"
  GEOIP_BLOCKED_COUNTRIES = ENV.fetch("GEOIP_BLOCKED_COUNTRIES", "").split(',').map(&.strip).reject(&.empty?)
  GEOIP_ALLOWED_COUNTRIES = ENV.fetch("GEOIP_ALLOWED_COUNTRIES", "").split(',').map(&.strip).reject(&.empty?)
  GEOIP_MMDB_FILE         = ENV.fetch("GEOIP_MMDB_FILE", "")

  # Config file path
  CONFIG_FILE = ENV.fetch("WAF_CONFIG_FILE", "config/waf.yml")

  # Config loader (optional, used if config file exists)
  @@config_loader : ConfigLoader? = nil
  @@pool_manager : ConnectionPoolManager? = nil
  begin
    if File.exists?(CONFIG_FILE)
      @@config_loader = ConfigLoader.new(CONFIG_FILE)
      Log.info { "YAML configuration file loaded: #{CONFIG_FILE}" }
    else
      Log.info { "YAML configuration file not found (#{CONFIG_FILE}), using environment variables" }
    end
  rescue ex
    Log.warn { "Failed to load YAML configuration: #{ex.message}, using environment variables" }
  end

  # Get values with environment variable override
  def self.get_config_value(env_key : String, default_value : String) : String
    return ENV[env_key] if ENV.has_key?(env_key) && !ENV[env_key].empty?

    # Get from config (if exists)
    config = @@config_loader.try(&.get_config)
    return default_value unless config

    case env_key
    when "UPSTREAM"
      @@config_loader.try(&.get_default_upstream) || default_value
    when "RULE_DIR"
      config.rules.try(&.directory) || default_value
    when "LOG_DIR"
      config.logging.try(&.log_dir) || default_value
    when "OBSERVE"
      (config.mode == "observe") ? "true" : "false"
    else
      default_value
    end
  end

  # Effective configuration values (with env override)
  EFFECTIVE_UPSTREAM     = get_config_value("UPSTREAM", UPSTREAM)
  EFFECTIVE_RULE_DIR     = get_config_value("RULE_DIR", RULE_DIR)
  EFFECTIVE_LOG_DIR      = get_config_value("LOG_DIR", LOG_DIR)
  EFFECTIVE_OBSERVE_MODE = get_config_value("OBSERVE", OBSERVE_MODE ? "true" : "false") == "true"

  # Global bileşenler
  @@rule_loader = RuleLoader.new(EFFECTIVE_RULE_DIR)
  @@evaluator = Evaluator.new(@@rule_loader, EFFECTIVE_OBSERVE_MODE, BODY_LIMIT)

  # Connection pool manager initialize et
  @@pool_manager = begin
    if config_loader = @@config_loader
      config = config_loader.get_config
      pool_config = config.try(&.connection_pooling)
      if pool_config && pool_config.enabled
        ConnectionPoolManager.new(pool_config)
      else
        nil
      end
    else
      nil
    end
  end

  @@proxy_client = begin
    retry_count = 3 # Default
    if config_loader = @@config_loader
      config = config_loader.get_config
      if upstream_config = config.try(&.upstream)
        retry_count = upstream_config.retry
      end
    end
    ProxyClient.new(EFFECTIVE_UPSTREAM, UPSTREAM_HOST_HEADER, PRESERVE_ORIGINAL_HOST, @@pool_manager, retry_count)
  end
  @@metrics = Metrics.new
  @@rate_limiter = RATE_LIMIT_ENABLED ? RateLimiter.new(
    RATE_LIMIT_DEFAULT,
    RATE_LIMIT_WINDOW_SEC,
    RATE_LIMIT_BLOCK_DURATION_SEC
  ) : nil
  @@ip_filter = IP_FILTER_ENABLED ? IPFilter.new(true) : IPFilter.new(false)

  # IP listelerini yükle
  if IP_FILTER_ENABLED
    if !IP_WHITELIST_FILE.empty? && File.exists?(IP_WHITELIST_FILE)
      @@ip_filter.load_from_file(IP_WHITELIST_FILE, :whitelist)
    end
    if !IP_BLACKLIST_FILE.empty? && File.exists?(IP_BLACKLIST_FILE)
      @@ip_filter.load_from_file(IP_BLACKLIST_FILE, :blacklist)
    end
  end

  # GeoIP filter
  @@geoip_filter = GEOIP_ENABLED ? GeoIPFilter.new(
    true,
    GEOIP_BLOCKED_COUNTRIES,
    GEOIP_ALLOWED_COUNTRIES
  ) : GeoIPFilter.new(false)
  @@structured_logger = StructuredLogger.new(
    EFFECTIVE_LOG_DIR,
    "waf",
    LOG_MAX_SIZE_MB,
    LOG_RETENTION_DAYS,
    LOG_QUEUE_SIZE,
    LOG_BATCH_SIZE,
    LOG_FLUSH_INTERVAL_MS
  )
  @@audit_logger = LOG_ENABLE_AUDIT ? AuditLogger.new(
    EFFECTIVE_LOG_DIR,
    "audit",
    AUDIT_LOG_MAX_SIZE_MB,
    AUDIT_LOG_RETENTION_DAYS,
    LOG_QUEUE_SIZE,
    LOG_BATCH_SIZE,
    LOG_FLUSH_INTERVAL_MS
  ) : nil

  # İlk kural sayısını metriğe kaydet
  @@metrics.set_rules_loaded(@@rule_loader.rule_count)

  # Config reload metodu - graceful reload
  def self.reload_config
    return unless config_loader = @@config_loader

    begin
      old_config = config_loader.get_config
      config_loader.load_config
      new_config = config_loader.get_config

      return unless old_config && new_config

      Log.info { "Starting config graceful reload..." }

      # Did rate limiting settings change?
      old_rl = old_config.rate_limiting
      new_rl = new_config.rate_limiting
      rl_changed = (old_rl.nil? != new_rl.nil?) || (old_rl && new_rl && (
        old_rl.not_nil!.enabled != new_rl.not_nil!.enabled ||
        old_rl.not_nil!.default_limit != new_rl.not_nil!.default_limit ||
        old_rl.not_nil!.window != new_rl.not_nil!.window ||
        old_rl.not_nil!.block_duration != new_rl.not_nil!.block_duration
      ))
      if rl_changed
        if new_rl && new_rl.enabled
          # Recreate rate limiter (existing states will be lost but this is acceptable)
          @@rate_limiter = RateLimiter.new(
            new_rl.default_limit,
            parse_duration_sec(new_rl.window),
            parse_duration_sec(new_rl.block_duration)
          )
          Log.info { "Rate limiter reconfigured: #{new_rl.default_limit}/#{new_rl.window}" }
        else
          @@rate_limiter = nil
          Log.info { "Rate limiting disabled" }
        end
      end

      # Did IP filtering settings change?
      old_ip = old_config.ip_filtering
      new_ip = new_config.ip_filtering
      ip_changed = (old_ip.nil? != new_ip.nil?) || (old_ip && new_ip && (
        old_ip.not_nil!.enabled != new_ip.not_nil!.enabled ||
        old_ip.not_nil!.whitelist_file != new_ip.not_nil!.whitelist_file ||
        old_ip.not_nil!.blacklist_file != new_ip.not_nil!.blacklist_file
      ))
      if ip_changed
        if new_ip && new_ip.enabled
          # Recreate IP filter and load files
          @@ip_filter = IPFilter.new(true)
          if whitelist_file = new_ip.whitelist_file
            if File.exists?(whitelist_file)
              @@ip_filter.load_from_file(whitelist_file, :whitelist)
              Log.info { "IP whitelist reloaded: #{whitelist_file}" }
            end
          end
          if blacklist_file = new_ip.blacklist_file
            if File.exists?(blacklist_file)
              @@ip_filter.load_from_file(blacklist_file, :blacklist)
              Log.info { "IP blacklist reloaded: #{blacklist_file}" }
            end
          end
        else
          @@ip_filter = IPFilter.new(false)
          Log.info { "IP filtering disabled" }
        end
      end

      # Did GeoIP settings change?
      old_geoip = old_config.geoip
      new_geoip = new_config.geoip
      geoip_changed = (old_geoip.nil? != new_geoip.nil?) || (old_geoip && new_geoip && (
        old_geoip.not_nil!.enabled != new_geoip.not_nil!.enabled ||
        old_geoip.not_nil!.mmdb_file != new_geoip.not_nil!.mmdb_file ||
        old_geoip.not_nil!.blocked_countries != new_geoip.not_nil!.blocked_countries ||
        old_geoip.not_nil!.allowed_countries != new_geoip.not_nil!.allowed_countries
      ))
      if geoip_changed
        if new_geoip && new_geoip.enabled
          @@geoip_filter = GeoIPFilter.new(
            true,
            new_geoip.blocked_countries,
            new_geoip.allowed_countries
          )
          Log.info { "GeoIP filter reconfigured" }
        else
          @@geoip_filter = GeoIPFilter.new(false)
          Log.info { "GeoIP filtering disabled" }
        end
      end

      # Domain configurations changed - only log (ProxyClient works dynamically)
      old_domains_count = old_config.domains.size
      new_domains_count = new_config.domains.size
      if old_domains_count != new_domains_count
        Log.info { "Domain configurations updated: #{old_domains_count} -> #{new_domains_count} domains" }
      end

      Log.info { "Config graceful reload completed" }
    rescue ex
      Log.error { "Config reload error: #{ex.message}" }
      Log.error { ex.backtrace.join("\n") if ex.backtrace }
      @@structured_logger.log_error(ex, {"context" => "config_reload"})
    end
  end

  # Duration string'i (örn: "30s", "5m") saniyeye çevir
  private def self.parse_duration_sec(duration_str : String) : Int32
    duration_str = duration_str.strip.downcase
    if duration_str.ends_with?("s")
      duration_str[0..-2].to_i? || 60
    elsif duration_str.ends_with?("m")
      (duration_str[0..-2].to_i? || 1) * 60
    elsif duration_str.ends_with?("h")
      (duration_str[0..-2].to_i? || 1) * 3600
    else
      duration_str.to_i? || 60
    end
  end

  # Start hot-reload fiber
  spawn do
    loop do
      sleep RELOAD_INTERVAL.seconds
      begin
        @@rule_loader.check_and_reload
        @@metrics.set_rules_loaded(@@rule_loader.rule_count)

        # Config hot-reload - graceful reload if there are changes
        if config_loader = @@config_loader
          if config_loader.check_and_reload
            reload_config
          end
        end
      rescue ex
        Log.error { "Hot-reload error: #{ex.message}" }
        @@structured_logger.log_error(ex, {"context" => "hot_reload"})
      end
    end
  end

  # Start log cleanup fiber
  spawn do
    loop do
      sleep 1.hour
      begin
        # Clean up old log files
        rotator = LogRotator.new(LOG_DIR, LOG_MAX_SIZE_MB, LOG_RETENTION_DAYS)
        rotator.cleanup_old_logs("waf")
        if LOG_ENABLE_AUDIT
          audit_rotator = LogRotator.new(LOG_DIR, AUDIT_LOG_MAX_SIZE_MB, AUDIT_LOG_RETENTION_DAYS)
          audit_rotator.cleanup_old_logs("audit")
        end
      rescue ex
        Log.error { "Log cleanup error: #{ex.message}" }
      end
    end
  end

  # Graceful shutdown handler
  Signal::INT.trap do
    Log.info { "SIGINT received, starting graceful shutdown..." }
    shutdown
    exit 0
  end

  Signal::TERM.trap do
    Log.info { "SIGTERM received, starting graceful shutdown..." }
    shutdown
    exit 0
  end

  # SIGHUP signal handler - config hot-reload
  Signal::HUP.trap do
    Log.info { "SIGHUP received, starting configuration graceful reload..." }
    begin
      reload_config
      Log.info { "Configuration successfully graceful reloaded" }
    rescue ex
      Log.error { "Error while reloading configuration: #{ex.message}" }
      @@structured_logger.log_error(ex, {"context" => "sighup_reload"})
    end
  end

  Log.info { "Starting WAF..." }
  Log.info { "RULE_DIR: #{RULE_DIR}" }
  Log.info { "UPSTREAM: #{UPSTREAM}" }
  Log.info { "UPSTREAM_HOST_HEADER: #{UPSTREAM_HOST_HEADER.empty? ? "(will be taken from upstream URI)" : UPSTREAM_HOST_HEADER}" }
  Log.info { "PRESERVE_ORIGINAL_HOST: #{PRESERVE_ORIGINAL_HOST}" }
  Log.info { "OBSERVE_MODE: #{OBSERVE_MODE}" }
  Log.info { "BODY_LIMIT: #{BODY_LIMIT} bytes" }
  Log.info { "RELOAD_INTERVAL: #{RELOAD_INTERVAL} seconds" }
  Log.info { "LOG_DIR: #{LOG_DIR}" }
  Log.info { "LOG_ENABLE_AUDIT: #{LOG_ENABLE_AUDIT}" }
  Log.info { "RATE_LIMIT_ENABLED: #{RATE_LIMIT_ENABLED}" }
  if RATE_LIMIT_ENABLED
    Log.info { "RATE_LIMIT_DEFAULT: #{RATE_LIMIT_DEFAULT}/#{RATE_LIMIT_WINDOW_SEC}s" }
    Log.info { "RATE_LIMIT_BLOCK_DURATION: #{RATE_LIMIT_BLOCK_DURATION_SEC}s" }
  end
  Log.info { "IP_FILTER_ENABLED: #{IP_FILTER_ENABLED}" }
  if IP_FILTER_ENABLED
    Log.info { "IP_WHITELIST_FILE: #{IP_WHITELIST_FILE.empty? ? "(yok)" : IP_WHITELIST_FILE}" }
    Log.info { "IP_BLACKLIST_FILE: #{IP_BLACKLIST_FILE.empty? ? "(yok)" : IP_BLACKLIST_FILE}" }
    stats = @@ip_filter.stats
    Log.info { "IP Filter Stats: Whitelist IPs=#{stats["whitelist_ips"]}, Blacklist IPs=#{stats["blacklist_ips"]}, Whitelist CIDRs=#{stats["whitelist_cidrs"]}, Blacklist CIDRs=#{stats["blacklist_cidrs"]}" }
  end
  Log.info { "GEOIP_ENABLED: #{GEOIP_ENABLED}" }
  if GEOIP_ENABLED
    Log.info { "GEOIP_MMDB_FILE: #{GEOIP_MMDB_FILE.empty? ? "(yok, API kullanılacak)" : GEOIP_MMDB_FILE}" }
    Log.info { "GEOIP_BLOCKED_COUNTRIES: #{GEOIP_BLOCKED_COUNTRIES.empty? ? "(yok)" : GEOIP_BLOCKED_COUNTRIES.join(", ")}" }
    Log.info { "GEOIP_ALLOWED_COUNTRIES: #{GEOIP_ALLOWED_COUNTRIES.empty? ? "(yok)" : GEOIP_ALLOWED_COUNTRIES.join(", ")}" }
    geoip_stats = @@geoip_filter.stats
    Log.info { "GeoIP Stats: Blocked Countries=#{geoip_stats["blocked_countries"]}, Allowed Countries=#{geoip_stats["allowed_countries"]}, Cache Size=#{geoip_stats["cache_size"]}" }
  end

  # Getter metodları
  def self.metrics : Metrics
    @@metrics
  end

  def self.rule_loader : RuleLoader
    @@rule_loader
  end

  def self.evaluator : Evaluator
    @@evaluator
  end

  def self.proxy_client : ProxyClient
    @@proxy_client
  end

  def self.structured_logger : StructuredLogger
    @@structured_logger
  end

  def self.audit_logger : AuditLogger?
    @@audit_logger
  end

  def self.rate_limiter : RateLimiter?
    @@rate_limiter
  end

  def self.ip_filter : IPFilter
    @@ip_filter
  end

  def self.geoip_filter : GeoIPFilter
    @@geoip_filter
  end

  def self.config_loader : ConfigLoader?
    @@config_loader
  end

  def self.pool_manager : ConnectionPoolManager?
    @@pool_manager
  end

  def self.shutdown
    Log.info { "WAF kapatılıyor..." }
    @@pool_manager.try(&.shutdown_all)
    @@structured_logger.shutdown
    @@audit_logger.try(&.shutdown)
    Log.info { "WAF kapatıldı" }
  end
end

# Metrics endpoint
get "/metrics" do |env|
  env.response.content_type = "text/plain; version=0.0.4"
  KemalWAF.metrics.to_prometheus
end

# Health check endpoint
get "/health" do |env|
  env.response.content_type = "application/json"
  {
    status:       "healthy",
    rules_loaded: KemalWAF.rule_loader.rule_count,
    observe_mode: KemalWAF::OBSERVE_MODE,
  }.to_json
end

# Pass all other requests through WAF
before_all do |env|
  # Skip metrics and health endpoints
  next if env.request.path == "/metrics"
  next if env.request.path == "/health"

  # Create request ID
  request_id = UUID.random.to_s
  env.set("request_id", request_id)
  start_time = Time.monotonic
  # Store Time.monotonic as nanoseconds (Float64)
  env.set("request_start_time_ns", start_time.total_nanoseconds.to_f)

  KemalWAF.metrics.increment_requests

  # Extract client IP
  client_ip = extract_client_ip(env.request)

  # IP filtering check (before rate limiting)
  if ip_filter = KemalWAF.ip_filter
    ip_filter_result = ip_filter.allowed?(client_ip)

    unless ip_filter_result.allowed
      Log.warn { "IP blocked: IP=#{client_ip}, Reason=#{ip_filter_result.reason}, Source=#{ip_filter_result.source}" }
      KemalWAF.metrics.increment_blocked

      # Structured log yaz
      result = KemalWAF::EvaluationResult.new(
        blocked: true,
        message: "IP blocked: #{ip_filter_result.reason}",
        rule_id: nil
      )
      KemalWAF.structured_logger.log_request(env.request, result, Time::Span.zero, request_id, Time.utc)

      # Audit log yaz
      if audit_logger = KemalWAF.audit_logger
        audit_logger.log_security_event(
          "IP_BLOCKED",
          "IP:#{client_ip} | Reason:#{ip_filter_result.reason} | Source:#{ip_filter_result.source}",
          request_id
        )
      end

      env.response.status_code = 403
      env.response.content_type = "application/json"
      env.response.print({
        error:   "Forbidden",
        message: "IP address blocked: #{ip_filter_result.reason}",
        reason:  ip_filter_result.reason,
        source:  ip_filter_result.source,
      }.to_json)
      env.set("waf_blocked", true)
      # halt env çağrıldığında Kemal response'u otomatik gönderir, close'a gerek yok
      halt env, 403
    end
  end

  # GeoIP filtering check (after IP filtering)
  if geoip_filter = KemalWAF.geoip_filter
    blocked, reason = geoip_filter.blocked?(client_ip)

    if blocked
      Log.warn { "GeoIP blocked: IP=#{client_ip}, Reason=#{reason}" }
      KemalWAF.metrics.increment_blocked

      # Structured log yaz
      result = KemalWAF::EvaluationResult.new(
        blocked: true,
        message: "GeoIP blocked: #{reason}",
        rule_id: nil
      )
      KemalWAF.structured_logger.log_request(env.request, result, Time::Span.zero, request_id, Time.utc)

      # Audit log yaz
      if audit_logger = KemalWAF.audit_logger
        geoip_info = geoip_filter.lookup(client_ip)
        country_info = geoip_info ? "Country:#{geoip_info.country_code} (#{geoip_info.country_name})" : "Country:Unknown"
        audit_logger.log_security_event(
          "GEOIP_BLOCKED",
          "IP:#{client_ip} | #{country_info} | Reason:#{reason}",
          request_id
        )
      end

      env.response.status_code = 403
      env.response.content_type = "application/json"
      env.response.print({
        error:   "Forbidden",
        message: "Access denied: #{reason}",
        reason:  reason,
        source:  "geoip",
      }.to_json)
      env.set("waf_blocked", true)
      # halt env çağrıldığında Kemal response'u otomatik gönderir, close'a gerek yok
      halt env, 403
    end
  end

  # Rate limiting kontrolü
  if rate_limiter = KemalWAF.rate_limiter
    rate_limit_result = rate_limiter.check(client_ip, env.request.path)

    unless rate_limit_result.allowed
      Log.warn { "Rate limit aşıldı: IP=#{client_ip}, Path=#{env.request.path}" }
      KemalWAF.metrics.increment_rate_limited

      # Structured log yaz
      KemalWAF.structured_logger.log_rate_limit(
        env.request,
        rate_limit_result,
        request_id,
        Time.utc
      )

      # Audit log yaz
      if audit_logger = KemalWAF.audit_logger
        audit_logger.log_security_event(
          "RATE_LIMIT_EXCEEDED",
          "IP:#{client_ip} | Path:#{env.request.path} | Limit:#{rate_limit_result.limit}",
          request_id
        )
      end

      # Rate limit header'larını ekle (response'a yazmadan önce)
      rate_limiter.set_headers(env.response, rate_limit_result)

      env.response.content_type = "text/html; charset=utf-8"

      message = "Rate limit exceeded. You are allowed #{rate_limit_result.limit} requests per time window. Please try again after #{rate_limit_result.reset_at.to_rfc3339}."
      html = render_waf_429(
        rate_limit_result.limit,
        rate_limit_result.reset_at,
        message
      )
      env.response.print(html)
      env.set("waf_blocked", true)
      halt env, 429
    else
      # Add headers if rate limit not exceeded
      rate_limiter.set_headers(env.response, rate_limit_result)
    end
  end

  # Read request body
  body = nil
  if env.request.body
    body = env.request.body.not_nil!.gets_to_end
    # Recreate body to be able to read it again
    env.request.body = IO::Memory.new(body)
  end

  # Evaluate rules
  result = KemalWAF.evaluator.evaluate(env.request, body)
  duration = Time.monotonic - start_time

  if result.blocked
    Log.info { "WAF blocked: #{result.message}" }
    KemalWAF.metrics.increment_blocked

    # Write structured log (non-blocking)
    KemalWAF.structured_logger.log_request(env.request, result, duration, request_id, Time.utc)

    # Write audit log (non-blocking)
    if audit_logger = KemalWAF.audit_logger
      if rule = KemalWAF.rule_loader.rules.find { |r| r.id == result.rule_id }
        audit_logger.log_block(env.request, rule, result, request_id)
      end
    end

    env.response.status_code = 403
    env.response.content_type = "text/html; charset=utf-8"

    html = render_waf_403(result.rule_id.to_s, result.message, KemalWAF::OBSERVE_MODE)
    env.response.print(html)
    # Mark as blocked by WAF
    env.set("waf_blocked", true)
    Log.debug { "Request short-circuited by WAF middleware" }
    # halt env çağrıldığında Kemal response'u otomatik gönderir, close'a gerek yok
    halt env, 403
  elsif result.observed
    KemalWAF.metrics.increment_observed
    # Write structured log (non-blocking)
    KemalWAF.structured_logger.log_request(env.request, result, duration, request_id, Time.utc)
  end

  # Request timing already recorded (request_start_time_ns)
end

# Client IP extraction helper
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

# Domain extraction helper
private def extract_domain(request : HTTP::Request) : String?
  host = request.headers["Host"]?
  return nil unless host

  # Port'u kaldır (örn: "example.com:8080" -> "example.com")
  host.split(':')[0].strip.downcase
end

# Proxy handler - forward all requests to upstream
# Same handler for all HTTP methods
def proxy_request(env)
  if env.get?("waf_blocked") || env.response.status_code == 403
    return ""
  end

  request_id = env.get?("request_id").try(&.as(String)) || UUID.random.to_s
  # We stored start_time as nanoseconds
  start_time_ns = env.get?("request_start_time_ns").try(&.as(Float64)) || Time.monotonic.total_nanoseconds.to_f

  # Read body
  body = nil
  if env.request.body
    body = env.request.body.not_nil!.gets_to_end
  end

  # Domain extraction and routing
  domain = extract_domain(env.request)
  host_header = env.request.headers["Host"]?
  KemalWAF::Log.info { "Request Host header: #{host_header}, Extracted domain: #{domain}" }

  upstream_url : String? = nil
  custom_host_header : String? = nil
  preserve_original_host : Bool? = nil
  verify_ssl : Bool? = nil

  # Do domain-based routing if config loader exists
  if config_loader = KemalWAF.config_loader
    if domain
      domain_config = config_loader.get_domain_config(domain)

      if domain_config
        # Configuration found for domain
        upstream_url = domain_config.default_upstream
        custom_host_header = domain_config.upstream_host_header.empty? ? nil : domain_config.upstream_host_header
        preserve_original_host = domain_config.preserve_original_host
        verify_ssl = domain_config.verify_ssl
        KemalWAF::Log.info { "Domain '#{domain}' için upstream bulundu: #{upstream_url}, verify_ssl: #{verify_ssl}" }
      else
        # Domain not in configuration - return 502 error
        KemalWAF::Log.warn { "Domain not found in configuration: '#{domain}' (Host: #{host_header})" }
        # Log available domains (for debug)
        if config = config_loader.get_config
          available_domains = config.domains.keys.join(", ")
          KemalWAF::Log.debug { "Mevcut domain'ler: #{available_domains}" }
        end
        env.response.status_code = 502
        env.response.content_type = "text/html; charset=utf-8"

        html = render_waf_502(
          domain || "unknown",
          "N/A",
          "Domain '#{domain}' is not configured in WAF. Please contact the administrator."
        )
        env.response.print(html)
        env.set("waf_blocked", true)
        env.response.close
        return ""
      end
    else
      # Host header yok - default upstream kullan
      upstream_url = config_loader.get_default_upstream
      if upstream_url.nil?
        KemalWAF::Log.error { "Host header yok ve default upstream tanımlı değil" }
        env.response.status_code = 502
        env.response.content_type = "text/html; charset=utf-8"

        html = render_waf_502(
          "unknown",
          "N/A",
          "No Host header provided and no default upstream configured."
        )
        env.response.print(html)
        env.set("waf_blocked", true)
        env.response.close
        return ""
      end
    end
  end

  # Upstream URL belirlenemedi ve default upstream yok
  if upstream_url.nil?
    # Default upstream'den al (backward compatibility)
    upstream_url = KemalWAF::EFFECTIVE_UPSTREAM
  end

  # Upstream URL hala yoksa hata döndür
  if upstream_url.nil? || upstream_url.empty?
    KemalWAF::Log.error { "Upstream URL belirlenemedi" }
    env.response.status_code = 502
    env.response.content_type = "text/html; charset=utf-8"

    html = render_waf_502(
      domain || "unknown",
      "N/A",
      "No upstream server configured for this request."
    )
    env.response.print(html)
    env.set("waf_blocked", true)
    env.response.close
    return ""
  end

  # Upstream'e yönlendir (dinamik upstream desteği ile)
  begin
    upstream_response = KemalWAF.proxy_client.forward(
      env.request,
      body,
      upstream_url: upstream_url,
      custom_host_header: custom_host_header,
      preserve_original_host: preserve_original_host,
      verify_ssl: verify_ssl
    )
  rescue ex
    KemalWAF::Log.error { "Upstream forward hatası: #{ex.message}" }
    env.response.status_code = 502
    env.response.content_type = "text/html; charset=utf-8"

    html = render_waf_502(
      domain || "unknown",
      upstream_url,
      "Failed to connect to upstream server: #{ex.message}"
    )
    env.response.print(html)
    env.set("waf_blocked", true)
    env.response.close
    return ""
  end

  # Eğer WAF tarafından engellenmişse (status 403), upstream response'unu kullanma
  if env.response.status_code == 403
    return ""
  end

  # Upstream yanıtını client'a aktar
  env.response.status_code = upstream_response.status_code.to_i

  # Yanıt başlıklarını kopyala
  upstream_response.headers.each do |key, values|
    key_lower = key.downcase

    # Bazı başlıkları atla (bunlar Kemal tarafından yönetiliyor)
    next if key_lower == "transfer-encoding"
    next if key_lower == "connection"
    next if key_lower == "content-length" # Kemal otomatik hesaplıyor

    # Content-Type gibi önemli header'ları özellikle koru
    values.each do |value|
      if key_lower == "content-type"
        # Content-Type'ı set et (add yerine set kullan, tekrar eklenmesin)
        env.response.content_type = value
      else
        env.response.headers.add(key, value)
      end
    end
  end

  # Request loglama (non-blocking) - başarılı istekler için
  current_time_ns = Time.monotonic.total_nanoseconds.to_f
  total_duration_ns = current_time_ns - start_time_ns
  total_duration = Time::Span.new(nanoseconds: total_duration_ns.to_i64)
  result = KemalWAF::EvaluationResult.new(blocked: false)
  KemalWAF.structured_logger.log_request(env.request, result, total_duration, request_id, Time.utc)

  upstream_response.body
end

# Proxy routes for all HTTP methods
# For root path and wildcard
get "/" do |env|
  proxy_request(env)
end

get "/*" do |env|
  proxy_request(env)
end

post "/" do |env|
  proxy_request(env)
end

post "/*" do |env|
  proxy_request(env)
end

put "/" do |env|
  proxy_request(env)
end

put "/*" do |env|
  proxy_request(env)
end

delete "/" do |env|
  proxy_request(env)
end

delete "/*" do |env|
  proxy_request(env)
end

patch "/" do |env|
  proxy_request(env)
end

patch "/*" do |env|
  proxy_request(env)
end

options "/" do |env|
  proxy_request(env)
end

options "/*" do |env|
  proxy_request(env)
end
Kemal.config.port = 3030

Kemal.run
