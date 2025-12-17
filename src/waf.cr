require "kemal"
require "json"
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
require "./waf_renderer"
require "./waf_helpers"
require "./tls_manager"
require "./memory_bounds"
require "./request_tracer"
require "./panic_isolator"
require "./letsencrypt_manager"

# Constants
DEFAULT_RETRY_COUNT = 3

module KemalWAF
  Log = ::Log.for("waf")

  # Configuration
  RULE_DIR               = ENV.fetch("RULE_DIR", "rules")
  UPSTREAM               = ENV.fetch("UPSTREAM", "http://localhost:8080")
  UPSTREAM_HOST_HEADER   = ENV.fetch("UPSTREAM_HOST_HEADER", "")                  # If empty, taken from upstream URI; if set, this is used
  PRESERVE_ORIGINAL_HOST = ENV.fetch("PRESERVE_ORIGINAL_HOST", "false") == "true" # Preserve original Host header from request
  OBSERVE_MODE           = ENV.fetch("OBSERVE", "false") == "true"
  BODY_LIMIT             = ENV.fetch("BODY_LIMIT_BYTES", "1048576").to_i
  RELOAD_INTERVAL        = ENV.fetch("RELOAD_INTERVAL_SEC", "5").to_i

  # Logging configuration
  LOG_DIR                  = ENV.fetch("LOG_DIR", "logs")
  LOG_MAX_SIZE_MB          = ENV.fetch("LOG_MAX_SIZE_MB", "100").to_i
  LOG_RETENTION_DAYS       = ENV.fetch("LOG_RETENTION_DAYS", "30").to_i
  AUDIT_LOG_MAX_SIZE_MB    = ENV.fetch("AUDIT_LOG_MAX_SIZE_MB", "50").to_i
  AUDIT_LOG_RETENTION_DAYS = ENV.fetch("AUDIT_LOG_RETENTION_DAYS", "90").to_i
  LOG_ENABLE_AUDIT         = ENV.fetch("LOG_ENABLE_AUDIT", "true") == "true"
  LOG_QUEUE_SIZE           = ENV.fetch("LOG_QUEUE_SIZE", "10000").to_i
  LOG_BATCH_SIZE           = ENV.fetch("LOG_BATCH_SIZE", "100").to_i
  LOG_FLUSH_INTERVAL_MS    = ENV.fetch("LOG_FLUSH_INTERVAL_MS", "1000").to_i

  # Rate limiting configuration
  RATE_LIMIT_ENABLED            = ENV.fetch("RATE_LIMIT_ENABLED", "true") == "true"
  RATE_LIMIT_DEFAULT            = ENV.fetch("RATE_LIMIT_DEFAULT", "100000").to_i
  RATE_LIMIT_WINDOW_SEC         = ENV.fetch("RATE_LIMIT_WINDOW_SEC", "60").to_i
  RATE_LIMIT_BLOCK_DURATION_SEC = ENV.fetch("RATE_LIMIT_BLOCK_DURATION_SEC", "300").to_i

  # IP filtering configuration
  IP_FILTER_ENABLED = ENV.fetch("IP_FILTER_ENABLED", "true") == "true"
  IP_WHITELIST_FILE = ENV.fetch("IP_WHITELIST_FILE", "")
  IP_BLACKLIST_FILE = ENV.fetch("IP_BLACKLIST_FILE", "")

  # GeoIP filtering configuration
  GEOIP_ENABLED           = ENV.fetch("GEOIP_ENABLED", "false") == "true"
  GEOIP_BLOCKED_COUNTRIES = ENV.fetch("GEOIP_BLOCKED_COUNTRIES", "").split(',').map(&.strip).reject(&.empty?)
  GEOIP_ALLOWED_COUNTRIES = ENV.fetch("GEOIP_ALLOWED_COUNTRIES", "").split(',').map(&.strip).reject(&.empty?)
  GEOIP_MMDB_FILE         = ENV.fetch("GEOIP_MMDB_FILE", "")

  # Config file path
  CONFIG_FILE = ENV.fetch("WAF_CONFIG_FILE", "config/waf.yml")

  # Server configuration (HTTP/HTTPS)
  HTTP_ENABLED  = ENV.fetch("HTTP_ENABLED", "true") == "true"
  HTTPS_ENABLED = ENV.fetch("HTTPS_ENABLED", "false") == "true"
  HTTP_PORT     = ENV.fetch("HTTP_PORT", "3030").to_i
  HTTPS_PORT    = ENV.fetch("HTTPS_PORT", "3443").to_i

  # TLS configuration
  TLS_CERT_FILE     = ENV.fetch("TLS_CERT_FILE", "")
  TLS_KEY_FILE      = ENV.fetch("TLS_KEY_FILE", "")
  TLS_AUTO_GENERATE = ENV.fetch("TLS_AUTO_GENERATE", "false") == "true"

  # Config loader (optional, used if config file exists)
  @@config_loader : ConfigLoader? = nil
  @@pool_manager : ConnectionPoolManager? = nil
  @@tls_manager : TLSManager? = nil

  # Track domains that should only be served over HTTP (failed to get SSL certificate)
  @@http_only_domains : Set(String) = Set(String).new
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
  # These are computed once at startup. For runtime changes, use config file hot-reload.
  # Configuration priority: ENV > YAML config > defaults
  EFFECTIVE_UPSTREAM     = get_config_value("UPSTREAM", UPSTREAM)
  EFFECTIVE_RULE_DIR     = get_config_value("RULE_DIR", RULE_DIR)
  EFFECTIVE_LOG_DIR      = get_config_value("LOG_DIR", LOG_DIR)
  EFFECTIVE_OBSERVE_MODE = get_config_value("OBSERVE", OBSERVE_MODE ? "true" : "false") == "true"

  # Server configuration (from config file or env)
  EFFECTIVE_HTTP_ENABLED = begin
    if config = @@config_loader.try(&.get_config)
      server_config = config.try(&.server)
      server_config ? server_config.http_enabled : HTTP_ENABLED
    else
      HTTP_ENABLED
    end
  end

  EFFECTIVE_HTTPS_ENABLED = begin
    if config = @@config_loader.try(&.get_config)
      server_config = config.try(&.server)
      server_config ? server_config.https_enabled : HTTPS_ENABLED
    else
      HTTPS_ENABLED
    end
  end

  EFFECTIVE_HTTP_PORT = begin
    if config = @@config_loader.try(&.get_config)
      server_config = config.try(&.server)
      server_config ? server_config.http_port : HTTP_PORT
    else
      HTTP_PORT
    end
  end

  EFFECTIVE_HTTPS_PORT = begin
    if config = @@config_loader.try(&.get_config)
      server_config = config.try(&.server)
      server_config ? server_config.https_port : HTTPS_PORT
    else
      HTTPS_PORT
    end
  end

  # Global components
  @@rule_loader = RuleLoader.new(EFFECTIVE_RULE_DIR)
  @@evaluator = Evaluator.new(@@rule_loader, EFFECTIVE_OBSERVE_MODE, BODY_LIMIT)

  # Initialize connection pool manager
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
    retry_count = DEFAULT_RETRY_COUNT
    if config_loader = @@config_loader
      config = config_loader.get_config
      if upstream_config = config.try(&.upstream)
        retry_count = upstream_config.retry
      end
    end
    ProxyClient.new(EFFECTIVE_UPSTREAM, UPSTREAM_HOST_HEADER, PRESERVE_ORIGINAL_HOST, @@pool_manager, retry_count)
  end

  # Initialize Let's Encrypt Manager
  @@letsencrypt_manager : LetsEncryptManager? = begin
    if EFFECTIVE_HTTPS_ENABLED
      letsencrypt_staging = ENV.fetch("LETSENCRYPT_STAGING", "false") == "true"
      LetsEncryptManager.new(
        cert_dir: "config/certs/letsencrypt",
        use_staging: letsencrypt_staging
      )
    else
      nil
    end
  end

  # Initialize SNI Manager
  @@sni_manager : SNIManager? = begin
    if EFFECTIVE_HTTPS_ENABLED
      sni_manager = SNIManager.new("config/certs")

      # Domain sertifikalarını yükle
      if config_loader = @@config_loader
        config = config_loader.get_config
        if config
          sni_manager.load_from_domain_configs(config.domains, @@letsencrypt_manager)
        end
      end

      sni_manager
    else
      nil
    end
  end

  # Initialize TLS Manager
  @@tls_manager = begin
    if EFFECTIVE_HTTPS_ENABLED
      tls_config = nil
      if config_loader = @@config_loader
        config = config_loader.get_config
        server_config = config.try(&.server)
        tls_config = server_config.try(&.tls) if server_config
      end

      cert_file = tls_config ? tls_config.cert_file : (TLS_CERT_FILE.empty? ? nil : TLS_CERT_FILE)
      key_file = tls_config ? tls_config.key_file : (TLS_KEY_FILE.empty? ? nil : TLS_KEY_FILE)
      auto_generate = tls_config ? tls_config.auto_generate : TLS_AUTO_GENERATE
      auto_cert_dir = tls_config ? tls_config.auto_cert_dir : "config/certs"
      tls_ciphers = tls_config ? tls_config.tls_ciphers : nil

      TLSManager.new(
        cert_file: cert_file,
        key_file: key_file,
        auto_generate: auto_generate,
        auto_cert_dir: auto_cert_dir,
        tls_ciphers: tls_ciphers
      )
    else
      nil
    end
  end
  @@metrics = Metrics.new
  @@rate_limiter = RATE_LIMIT_ENABLED ? RateLimiter.new(
    RATE_LIMIT_DEFAULT,
    RATE_LIMIT_WINDOW_SEC,
    RATE_LIMIT_BLOCK_DURATION_SEC
  ) : nil
  @@ip_filter = IP_FILTER_ENABLED ? IPFilter.new(true) : IPFilter.new(false)

  # Load IP lists
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

  # Record initial rule count to metrics
  @@metrics.set_rules_loaded(@@rule_loader.rule_count)

  # Helper: Check if config section changed
  private def self.config_section_changed?(old_section, new_section, &block : -> Bool) : Bool
    if old_section && new_section
      block.call
    else
      old_section.nil? != new_section.nil?
    end
  end

  # Config reload method - graceful reload
  def self.reload_config
    return unless config_loader = @@config_loader

    begin
      old_config = config_loader.get_config
      config_loader.load_config
      new_config = config_loader.get_config

      return unless old_config && new_config

      Log.info { "Starting config graceful reload..." }

      # Did rate limiting settings change?
      old_rate_limit = old_config.rate_limiting
      new_rate_limit = new_config.rate_limiting
      rate_limit_changed = config_section_changed?(old_rate_limit, new_rate_limit) do
        if old_rate_limit && new_rate_limit
          old_rate_limit.enabled != new_rate_limit.enabled ||
            old_rate_limit.default_limit != new_rate_limit.default_limit ||
            old_rate_limit.window != new_rate_limit.window ||
            old_rate_limit.block_duration != new_rate_limit.block_duration
        else
          false
        end
      end
      if rate_limit_changed
        if new_rate_limit && new_rate_limit.enabled
          # Recreate rate limiter (existing states will be lost but this is acceptable)
          @@rate_limiter = RateLimiter.new(
            new_rate_limit.default_limit,
            parse_duration_sec(new_rate_limit.window),
            parse_duration_sec(new_rate_limit.block_duration)
          )
          Log.info { "Rate limiter reconfigured: #{new_rate_limit.default_limit}/#{new_rate_limit.window}" }
        else
          @@rate_limiter = nil
          Log.info { "Rate limiting disabled" }
        end
      end

      # Did IP filtering settings change?
      old_ip_filter = old_config.ip_filtering
      new_ip_filter = new_config.ip_filtering
      ip_filter_changed = config_section_changed?(old_ip_filter, new_ip_filter) do
        if old_ip_filter && new_ip_filter
          old_ip_filter.enabled != new_ip_filter.enabled ||
            old_ip_filter.whitelist_file != new_ip_filter.whitelist_file ||
            old_ip_filter.blacklist_file != new_ip_filter.blacklist_file
        else
          false
        end
      end
      if ip_filter_changed
        if new_ip_filter && new_ip_filter.enabled
          # Recreate IP filter and load files
          @@ip_filter = IPFilter.new(true)
          if whitelist_file = new_ip_filter.whitelist_file
            if File.exists?(whitelist_file)
              @@ip_filter.load_from_file(whitelist_file, :whitelist)
              Log.info { "IP whitelist reloaded: #{whitelist_file}" }
            end
          end
          if blacklist_file = new_ip_filter.blacklist_file
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
      old_geoip_config = old_config.geoip
      new_geoip_config = new_config.geoip
      geoip_config_changed = config_section_changed?(old_geoip_config, new_geoip_config) do
        if old_geoip_config && new_geoip_config
          old_geoip_config.enabled != new_geoip_config.enabled ||
            old_geoip_config.mmdb_file != new_geoip_config.mmdb_file ||
            old_geoip_config.blocked_countries != new_geoip_config.blocked_countries ||
            old_geoip_config.allowed_countries != new_geoip_config.allowed_countries
        else
          false
        end
      end
      if geoip_config_changed
        if new_geoip_config && new_geoip_config.enabled
          @@geoip_filter = GeoIPFilter.new(
            true,
            new_geoip_config.blocked_countries,
            new_geoip_config.allowed_countries
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

  # Start certificate renewal fiber (Let's Encrypt auto-renewal)
  spawn do
    # İlk kontrolü 1 saat sonra yap
    sleep 1.hour

    loop do
      begin
        if letsencrypt_manager = @@letsencrypt_manager
          if sni_manager = @@sni_manager
            if config_loader = @@config_loader
              config = config_loader.get_config
              if config
                # Yenileme gereken sertifikaları kontrol et
                config.domains.each do |domain, domain_config|
                  if domain_config.use_letsencrypt?
                    if letsencrypt_manager.needs_renewal?(domain, 30)
                      Log.info { "Certificate renewal needed for '#{domain}'" }
                      if letsencrypt_manager.renew_certificate(domain, domain_config.letsencrypt_email)
                        # Sertifika yenilendi, SNI manager'ı güncelle
                        cert_path = letsencrypt_manager.get_cert_path(domain)
                        key_path = letsencrypt_manager.get_key_path(domain)
                        if File.exists?(cert_path) && File.exists?(key_path)
                          sni_manager.add_domain_certificate(domain, cert_path, key_path, true)
                          Log.info { "Certificate renewed and reloaded for '#{domain}'" }
                        end
                      else
                        Log.error { "Failed to renew certificate for '#{domain}'" }
                      end
                    end
                  end
                end
              end
            end
          end
        end
      rescue ex
        Log.error { "Certificate renewal error: #{ex.message}" }
        @@structured_logger.log_error(ex, {"context" => "cert_renewal"})
      end

      # Her 12 saatte bir kontrol et
      sleep 12.hours
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
    Log.info { "IP_WHITELIST_FILE: #{IP_WHITELIST_FILE.empty? ? "(none)" : IP_WHITELIST_FILE}" }
    Log.info { "IP_BLACKLIST_FILE: #{IP_BLACKLIST_FILE.empty? ? "(none)" : IP_BLACKLIST_FILE}" }
    stats = @@ip_filter.stats
    Log.info { "IP Filter Stats: Whitelist IPs=#{stats["whitelist_ips"]}, Blacklist IPs=#{stats["blacklist_ips"]}, Whitelist CIDRs=#{stats["whitelist_cidrs"]}, Blacklist CIDRs=#{stats["blacklist_cidrs"]}" }
  end
  Log.info { "GEOIP_ENABLED: #{GEOIP_ENABLED}" }
  if GEOIP_ENABLED
    Log.info { "GEOIP_MMDB_FILE: #{GEOIP_MMDB_FILE.empty? ? "(none, API will be used)" : GEOIP_MMDB_FILE}" }
    Log.info { "GEOIP_BLOCKED_COUNTRIES: #{GEOIP_BLOCKED_COUNTRIES.empty? ? "(none)" : GEOIP_BLOCKED_COUNTRIES.join(", ")}" }
    Log.info { "GEOIP_ALLOWED_COUNTRIES: #{GEOIP_ALLOWED_COUNTRIES.empty? ? "(none)" : GEOIP_ALLOWED_COUNTRIES.join(", ")}" }
    geoip_stats = @@geoip_filter.stats
    Log.info { "GeoIP Stats: Blocked Countries=#{geoip_stats["blocked_countries"]}, Allowed Countries=#{geoip_stats["allowed_countries"]}, Cache Size=#{geoip_stats["cache_size"]}" }
  end

  # Server configuration logging
  Log.info { "HTTP_ENABLED: #{EFFECTIVE_HTTP_ENABLED}" }
  Log.info { "HTTPS_ENABLED: #{EFFECTIVE_HTTPS_ENABLED}" }
  if EFFECTIVE_HTTP_ENABLED
    Log.info { "HTTP_PORT: #{EFFECTIVE_HTTP_PORT}" }
  end
  if EFFECTIVE_HTTPS_ENABLED
    Log.info { "HTTPS_PORT: #{EFFECTIVE_HTTPS_PORT}" }

    # Create initial SSL certificates for Let's Encrypt enabled domains
    create_initial_certificates

    # SNI Manager logging
    if sni_manager = @@sni_manager
      domain_certs = sni_manager.list_domains
      if domain_certs.size > 0
        Log.info { "SNI: #{domain_certs.size} domain certificate(s) loaded" }
        domain_certs.each do |domain|
          Log.info { "  - #{domain}" }
        end
      end
    end

    # HTTP-only domains logging
    if @@http_only_domains.size > 0
      Log.warn { "HTTP-only domains (SSL certificate not available): #{@@http_only_domains.size}" }
      @@http_only_domains.each do |domain|
        Log.warn { "  - #{domain}" }
      end
    end

    # Let's Encrypt Manager logging
    if le_manager = @@letsencrypt_manager
      staging_mode = le_manager.staging? ? " (STAGING)" : ""
      Log.info { "Let's Encrypt: Enabled#{staging_mode}" }
    end

    # TLS Manager logging
    if tls_manager = @@tls_manager
      tls_config = @@config_loader.try(&.get_config).try(&.server).try(&.tls)
      if tls_config
        if tls_config.auto_generate
          Log.info { "TLS: Auto-generating self-signed certificate (fallback)" }
        elsif tls_config.cert_file && tls_config.key_file
          Log.info { "TLS: Using default certificate files - cert=#{tls_config.cert_file}, key=#{tls_config.key_file}" }
        end
      elsif TLS_AUTO_GENERATE
        Log.info { "TLS: Auto-generating self-signed certificate (from env)" }
      elsif !TLS_CERT_FILE.empty? && !TLS_KEY_FILE.empty?
        Log.info { "TLS: Using certificate files (from env) - cert=#{TLS_CERT_FILE}, key=#{TLS_KEY_FILE}" }
      end
    end
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

  def self.tls_manager : TLSManager?
    @@tls_manager
  end

  def self.sni_manager : SNIManager?
    @@sni_manager
  end

  def self.letsencrypt_manager : LetsEncryptManager?
    @@letsencrypt_manager
  end

  def self.http_only_domains : Set(String)
    @@http_only_domains
  end

  def self.is_http_only_domain?(domain : String) : Bool
    @@http_only_domains.includes?(domain)
  end

  def self.add_http_only_domain(domain : String)
    @@http_only_domains.add(domain)
    Log.warn { "Domain '#{domain}' marked as HTTP-only (SSL certificate not available)" }
  end

  # Create initial SSL certificates for domains with letsencrypt_enabled: true
  def self.create_initial_certificates
    Log.info { "Starting initial SSL certificate creation..." }

    config_loader = @@config_loader
    letsencrypt_manager = @@letsencrypt_manager
    sni_manager = @@sni_manager

    return unless config_loader && letsencrypt_manager

    config = config_loader.get_config
    return unless config

    created_count = 0
    failed_count = 0

    config.domains.each do |domain, domain_config|
      next unless domain_config.use_letsencrypt?

      Log.info { "Processing SSL certificate for domain '#{domain}'..." }

      # Check if certificate already exists and is valid
      cert_path = letsencrypt_manager.get_cert_path(domain)
      key_path = letsencrypt_manager.get_key_path(domain)

      if File.exists?(cert_path) && File.exists?(key_path) && !letsencrypt_manager.needs_renewal?(domain, 30)
        Log.info { "Valid certificate already exists for '#{domain}'" }

        # Add to SNI manager
        if sni_mgr = sni_manager
          sni_mgr.add_domain_certificate(domain, cert_path, key_path, true)
        end

        created_count += 1
        next
      end

      # Try to create certificate
      begin
        if letsencrypt_manager.create_certificate(domain, domain_config.letsencrypt_email)
          Log.info { "SSL certificate created successfully for '#{domain}'" }

          # Add to SNI manager
          if sni_mgr = sni_manager
            cert_path = letsencrypt_manager.get_cert_path(domain)
            key_path = letsencrypt_manager.get_key_path(domain)
            if File.exists?(cert_path) && File.exists?(key_path)
              sni_mgr.add_domain_certificate(domain, cert_path, key_path, true)
            end
          end

          created_count += 1
        else
          Log.warn { "Failed to create SSL certificate for '#{domain}', marking as HTTP-only" }
          add_http_only_domain(domain)
          failed_count += 1
        end
      rescue ex
        Log.error { "Error creating SSL certificate for '#{domain}': #{ex.message}" }
        add_http_only_domain(domain)
        failed_count += 1
      end
    end

    Log.info { "Initial SSL certificate creation completed: #{created_count} created, #{failed_count} failed (HTTP-only)" }
  end

  def self.shutdown
    Log.info { "Shutting down WAF..." }
    @@pool_manager.try(&.shutdown_all)
    @@structured_logger.shutdown
    @@audit_logger.try(&.shutdown)
    Log.info { "WAF shut down" }
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

# ACME Challenge endpoint for Let's Encrypt HTTP-01 validation
# This endpoint is bypassed from WAF rules
get "/.well-known/acme-challenge/:token" do |env|
  token = env.params.url["token"]
  KemalWAF::Log.debug { "ACME challenge request for token: #{token}" }

  # Let's Encrypt manager'dan challenge içeriğini al
  if letsencrypt_manager = KemalWAF.letsencrypt_manager
    if content = letsencrypt_manager.read_challenge_file(token)
      env.response.content_type = "text/plain"
      content
    else
      KemalWAF::Log.warn { "ACME challenge token not found: #{token}" }
      env.response.status_code = 404
      env.response.content_type = "text/plain"
      "Token not found"
    end
  else
    KemalWAF::Log.warn { "Let's Encrypt manager not initialized" }
    env.response.status_code = 503
    env.response.content_type = "text/plain"
    "Let's Encrypt not configured"
  end
end

# Pass all other requests through WAF
before_all do |env|
  # Skip metrics, health and ACME challenge endpoints
  next if env.request.path == "/metrics"
  next if env.request.path == "/health"
  next if env.request.path.starts_with?("/.well-known/acme-challenge/")

  # Create request ID
  request_id = UUID.random.to_s
  env.set("request_id", request_id)
  start_time = Time.monotonic
  # Store Time.monotonic as nanoseconds (Float64)
  env.set("request_start_time_ns", start_time.total_nanoseconds.to_f)

  KemalWAF.metrics.increment_requests

  # Extract client IP
  client_ip = WAFHelpers.extract_client_ip(env.request)

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
      # When halt env is called, Kemal automatically sends the response, no need to close
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
      # When halt env is called, Kemal automatically sends the response, no need to close
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

      # Add rate limit headers (before writing to response)
      rate_limiter.set_headers(env.response, rate_limit_result)

      env.response.content_type = "text/html; charset=utf-8"

      message = "Rate limit exceeded. You are allowed #{rate_limit_result.limit} requests per time window. Please try again after #{rate_limit_result.reset_at.to_rfc3339}."
      html = WAFRenderer.render_429(
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
  if request_body = env.request.body
    body = request_body.gets_to_end
    # Recreate body to be able to read it again
    env.request.body = IO::Memory.new(body)
  end

  # Extract domain for domain-based evaluation
  domain = WAFHelpers.extract_domain(env.request)
  domain_eval_config : KemalWAF::DomainEvalConfig? = nil

  # Build domain evaluation config if domain config exists
  if domain && (config_loader = KemalWAF.config_loader)
    if domain_config = config_loader.get_domain_config(domain)
      # Build DomainEvalConfig from domain config
      enabled_rules = [] of Int32
      disabled_rules = [] of Int32

      if waf_rules = domain_config.waf_rules
        enabled_rules = waf_rules.enabled
        disabled_rules = waf_rules.disabled
      end

      domain_eval_config = KemalWAF::DomainEvalConfig.new(
        threshold: domain_config.waf_threshold,
        enabled_rules: enabled_rules,
        disabled_rules: disabled_rules
      )

      Log.debug { "Domain '#{domain}' WAF config: threshold=#{domain_config.waf_threshold}" }
    end
  end

  # Evaluate rules with domain-aware scoring
  result = KemalWAF.evaluator.evaluate_with_domain(env.request, body, domain_eval_config)
  duration = Time.monotonic - start_time

  if result.blocked
    # Log matched rules and scores for debugging
    if !result.matched_rules.empty?
      matched_info = result.matched_rules.map { |r| "#{r.rule_id}(#{r.score})" }.join(", ")
      Log.info { "WAF blocked: #{result.message} | Rules: #{matched_info} | Total: #{result.total_score}/#{result.threshold}" }
    else
      Log.info { "WAF blocked: #{result.message}" }
    end
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

    # Include score info in the message
    block_message = result.message
    if result.total_score > 0
      block_message = "#{result.message} (Score: #{result.total_score}/#{result.threshold})"
    end

    html = WAFRenderer.render_403(result.rule_id.to_s, block_message, KemalWAF::OBSERVE_MODE)
    env.response.print(html)
    # Mark as blocked by WAF
    env.set("waf_blocked", true)
    Log.debug { "Request short-circuited by WAF middleware" }
    # When halt env is called, Kemal automatically sends the response, no need to close
    halt env, 403
  elsif result.observed
    KemalWAF.metrics.increment_observed
    # Write structured log (non-blocking)
    KemalWAF.structured_logger.log_request(env.request, result, duration, request_id, Time.utc)

    # Log observed matches with scores
    if !result.matched_rules.empty?
      matched_info = result.matched_rules.map { |r| "#{r.rule_id}(#{r.score})" }.join(", ")
      Log.debug { "[OBSERVE] Rules matched: #{matched_info} | Total: #{result.total_score}/#{result.threshold}" }
    end
  end

  # Request timing already recorded (request_start_time_ns)
end

# Proxy handler - forward all requests to upstream
# Same handler for all HTTP methods
def proxy_request(env)
  if env.get?("waf_blocked") || env.response.status_code == 403
    return ""
  end

  request_id = env.get?("request_id").try(&.as?(String)) || UUID.random.to_s
  # We stored start_time as nanoseconds
  start_time_ns = env.get?("request_start_time_ns").try(&.as?(Float64)) || Time.monotonic.total_nanoseconds.to_f

  # Read body
  body = nil
  if request_body = env.request.body
    body = request_body.gets_to_end
  end

  # Domain extraction and routing
  domain = WAFHelpers.extract_domain(env.request)
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
        KemalWAF::Log.info { "Upstream found for domain '#{domain}': #{upstream_url}, verify_ssl: #{verify_ssl}" }
      else
        # Domain not in configuration - return 502 error
        KemalWAF::Log.warn { "Domain not found in configuration: '#{domain}' (Host: #{host_header})" }
        # Log available domains (for debug)
        if config = config_loader.get_config
          available_domains = config.domains.keys.join(", ")
          KemalWAF::Log.debug { "Available domains: #{available_domains}" }
        end
        env.response.status_code = 502
        env.response.content_type = "text/html; charset=utf-8"

        html = WAFRenderer.render_502(
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
      # No Host header - use default upstream
      upstream_url = config_loader.get_default_upstream
      if upstream_url.nil?
        KemalWAF::Log.error { "No Host header and no default upstream configured" }
        env.response.status_code = 502
        env.response.content_type = "text/html; charset=utf-8"

        html = WAFRenderer.render_502(
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

  # Return error if upstream URL still not determined
  if upstream_url.nil? || upstream_url.empty?
    KemalWAF::Log.error { "Upstream URL could not be determined" }
    env.response.status_code = 502
    env.response.content_type = "text/html; charset=utf-8"

    html = WAFRenderer.render_502(
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
    KemalWAF::Log.error { "Upstream forward error: #{ex.message}" }
    env.response.status_code = 502
    env.response.content_type = "text/html; charset=utf-8"

    html = WAFRenderer.render_502(
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

  # Forward upstream response to client
  env.response.status_code = upstream_response.status_code.to_i

  # Copy response headers
  upstream_response.headers.each do |key, values|
    key_lower = key.downcase

    # Skip some headers (these are managed by Kemal)
    next if key_lower == "transfer-encoding"
    next if key_lower == "connection"
    next if key_lower == "content-length" # Kemal calculates automatically

    # Preserve important headers like Content-Type
    values.each do |value|
      if key_lower == "content-type"
        # Set Content-Type (use set instead of add to avoid duplicates)
        env.response.content_type = value
      else
        env.response.headers.add(key, value)
      end
    end
  end

  # Request logging (non-blocking) - for successful requests
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

# Configure and start Kemal servers
if KemalWAF::EFFECTIVE_HTTP_ENABLED && KemalWAF::EFFECTIVE_HTTPS_ENABLED
  # Both HTTP and HTTPS enabled - start both servers
  KemalWAF::Log.info { "WAF will listen on HTTP port #{KemalWAF::EFFECTIVE_HTTP_PORT} and HTTPS port #{KemalWAF::EFFECTIVE_HTTPS_PORT}" }

  # Configure TLS for HTTPS
  if tls_manager = KemalWAF.tls_manager
    tls_context = tls_manager.get_tls_context
    if tls_context
      # Store TLS context in a variable that won't be nil
      final_tls_context = tls_context.not_nil!

      # Start HTTPS server in a fiber using Kemal's handlers
      spawn do
        begin
          https_server = HTTP::Server.new(Kemal.config.handlers) do |context|
            Kemal.config.handlers.each do |handler|
              handler.call(context)
              break if context.response.closed?
            end
          end

          https_server.bind_tls "0.0.0.0", KemalWAF::EFFECTIVE_HTTPS_PORT, final_tls_context
          KemalWAF::Log.info { "HTTPS server started on port #{KemalWAF::EFFECTIVE_HTTPS_PORT}" }
          https_server.listen
        rescue ex
          KemalWAF::Log.error { "HTTPS server error: #{ex.message}" }
          KemalWAF::Log.error { ex.inspect_with_backtrace }
        end
      end

      KemalWAF::Log.info { "TLS/SSL configured successfully" }
    else
      KemalWAF::Log.error { "Failed to configure TLS/SSL. HTTPS will not be available." }
      exit 1
    end
  else
    KemalWAF::Log.error { "TLS Manager not initialized. HTTPS will not be available." }
    exit 1
  end

  # Start HTTP server
  Kemal.config.port = KemalWAF::EFFECTIVE_HTTP_PORT
  Kemal.config.ssl = nil
  KemalWAF::Log.info { "HTTP server starting on port #{KemalWAF::EFFECTIVE_HTTP_PORT}" }
  Kemal.run
elsif KemalWAF::EFFECTIVE_HTTPS_ENABLED
  # Only HTTPS enabled
  Kemal.config.port = KemalWAF::EFFECTIVE_HTTPS_PORT
  KemalWAF::Log.info { "WAF will listen on HTTPS port #{KemalWAF::EFFECTIVE_HTTPS_PORT}" }

  if tls_manager = KemalWAF.tls_manager
    tls_context = tls_manager.get_tls_context
    if tls_context
      Kemal.config.ssl = tls_context
      KemalWAF::Log.info { "TLS/SSL configured successfully" }
    else
      KemalWAF::Log.error { "Failed to configure TLS/SSL. HTTPS will not be available." }
      exit 1
    end
  else
    KemalWAF::Log.error { "TLS Manager not initialized. HTTPS will not be available." }
    exit 1
  end

  Kemal.run
else
  # Only HTTP enabled (default)
  Kemal.config.port = KemalWAF::EFFECTIVE_HTTP_PORT
  Kemal.config.ssl = nil
  KemalWAF::Log.info { "WAF will listen on HTTP port #{KemalWAF::EFFECTIVE_HTTP_PORT}" }
  Kemal.run
end
