require "yaml"
require "uri"

module KemalWAF
  # Domain yapılandırması
  struct DomainConfig
    include YAML::Serializable

    property default_upstream : String
    property upstream_host_header : String = ""
    property preserve_original_host : Bool = false
    property verify_ssl : Bool = true # SSL sertifika doğrulaması (default: true)

    def initialize(@default_upstream : String, @upstream_host_header : String = "", @preserve_original_host : Bool = false, @verify_ssl : Bool = true)
    end
  end

  # WAF yapılandırması
  struct WAFConfig
    include YAML::Serializable

    property mode : String = "enforce"
    property upstream : UpstreamConfig? = nil
    property domains : Hash(String, DomainConfig) = {} of String => DomainConfig
    property rate_limiting : RateLimitingConfig? = nil
    property ip_filtering : IPFilteringConfig? = nil
    property geoip : GeoIPConfig? = nil
    property rules : RulesConfig? = nil
    property logging : LoggingConfig? = nil
    property metrics : MetricsConfig? = nil
    property connection_pooling : ConnectionPoolingConfig? = nil

    def initialize
    end
  end

  struct UpstreamConfig
    include YAML::Serializable

    property url : String
    property timeout : String = "30s"
    property retry : Int32 = 3
    property verify_ssl : Bool = true # SSL sertifika doğrulaması (default: true)
  end

  struct RateLimitingConfig
    include YAML::Serializable

    property enabled : Bool = true
    property default_limit : Int32 = 100
    property window : String = "60s"
    property block_duration : String = "300s"
  end

  struct IPFilteringConfig
    include YAML::Serializable

    property whitelist_file : String? = nil
    property blacklist_file : String? = nil
    property enabled : Bool = true
  end

  struct GeoIPConfig
    include YAML::Serializable

    property enabled : Bool = false
    property mmdb_file : String? = nil
    property blocked_countries : Array(String) = [] of String
    property allowed_countries : Array(String) = [] of String
  end

  struct RulesConfig
    include YAML::Serializable

    property directory : String = "rules"
    property reload_interval : String = "5s"
  end

  struct LoggingConfig
    include YAML::Serializable

    property level : String = "info"
    property format : String = "json"
    property audit_file : String? = nil
    property log_dir : String = "logs"
    property max_size_mb : Int32 = 100
    property retention_days : Int32 = 30
    property audit_max_size_mb : Int32 = 50
    property audit_retention_days : Int32 = 90
    property enable_audit : Bool = true
    property queue_size : Int32 = 10000
    property batch_size : Int32 = 100
    property flush_interval_ms : Int32 = 1000
  end

  struct MetricsConfig
    include YAML::Serializable

    property enabled : Bool = true
    property port : Int32 = 9090
  end

  struct ConnectionPoolingConfig
    include YAML::Serializable

    property enabled : Bool = true
    property pool_size : Int32 = 100
    property max_size : Int32 = 200
    property idle_timeout : String = "300s"
    property health_check : Bool = true

    def self.new_default : ConnectionPoolingConfig
      config = ConnectionPoolingConfig.allocate
      config.enabled = true
      config.pool_size = 100
      config.max_size = 200
      config.idle_timeout = "300s"
      config.health_check = true
      config
    end
  end

  # Yapılandırma yükleyici ve yöneticisi
  class ConfigLoader
    Log = ::Log.for("config_loader")

    @config_file : String
    @config : WAFConfig?
    @domains : Hash(String, DomainConfig)
    @mutex : Mutex
    @last_mtime : Time?

    def initialize(@config_file : String)
      @domains = {} of String => DomainConfig
      @mutex = Mutex.new
      @last_mtime = nil
      load_config
    end

    def load_config
      return unless File.exists?(@config_file)

      begin
        mtime = File.info(@config_file).modification_time
        return if @last_mtime && mtime == @last_mtime

        content = File.read(@config_file)
        yaml_data = YAML.parse(content)

        # YAML'da "waf:" root key'i var, onu extract et
        waf_node = yaml_data["waf"]?
        raise "Root key 'waf:' not found in YAML file" unless waf_node

        # WAFConfig struct'ına dönüştür
        config = WAFConfig.from_yaml(waf_node.to_yaml)

        # Validation
        validate_config(config)

        @mutex.synchronize do
          @config = config
          @domains = config.domains.dup
          @last_mtime = mtime
        end

        Log.info { "Configuration loaded: #{@config_file}" }
        Log.info { "#{@domains.size} domain configurations loaded" }
        # Debug: List domains
        domain_list = @domains.keys.map { |k| "'#{k}'" }.join(", ")
        Log.info { "Loaded domains: #{domain_list}" }
      rescue ex
        Log.error { "Failed to load configuration: #{ex.message}" }
        Log.error { ex.backtrace.join("\n") if ex.backtrace }
        raise "Configuration error: #{ex.message}"
      end
    end

    private def validate_config(config : WAFConfig)
      # Domain yapılandırmalarını validate et
      config.domains.each do |domain, domain_config|
        begin
          uri = URI.parse(domain_config.default_upstream)
          raise "Invalid upstream URL: #{domain_config.default_upstream}" unless uri.host
        rescue ex
          raise "Invalid upstream URL for domain '#{domain}': #{ex.message}"
        end
      end

      # Global upstream varsa validate et
      if upstream = config.upstream
        begin
          uri = URI.parse(upstream.url)
          raise "Invalid global upstream URL: #{upstream.url}" unless uri.host
        rescue ex
          raise "Invalid URL for global upstream: #{ex.message}"
        end
      end
    end

    def get_domain_config(domain : String) : DomainConfig?
      @mutex.synchronize do
        result = @domains[domain]?
        if result.nil?
          # Debug: Domain not found, log available domains
          available = @domains.keys.map { |k| "'#{k}'" }.join(", ")
          Log.debug { "Domain '#{domain}' not found. Available domains: #{available}" }
        end
        result
      end
    end

    def get_default_upstream : String?
      @mutex.synchronize do
        @config.try(&.upstream).try(&.url)
      end
    end

    def has_domain?(domain : String) : Bool
      @mutex.synchronize do
        @domains.has_key?(domain)
      end
    end

    def get_config : WAFConfig?
      @mutex.synchronize do
        @config
      end
    end

    def check_and_reload : Bool
      return false unless File.exists?(@config_file)

      mtime = File.info(@config_file).modification_time
      changed = if last_mtime = @last_mtime
                  mtime > last_mtime
                else
                  true
                end

      if changed
        Log.info { "Configuration file changed, reloading..." }
        load_config
        true
      else
        false
      end
    end

    def last_mtime : Time?
      @last_mtime
    end

    # Environment variable'dan değer al, yoksa config'den al
    def get_with_env_override(env_key : String, default_value : String? = nil) : String?
      env_value = ENV[env_key]?
      return env_value if env_value && !env_value.empty?

      # Config'den al
      config = get_config
      return default_value unless config

      case env_key
      when "UPSTREAM"
        get_default_upstream || default_value
      else
        default_value
      end
    end
  end
end
