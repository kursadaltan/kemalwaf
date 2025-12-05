require "yaml"
require "json"
require "file_utils"

module AdminPanel
  # Domain configuration for JSON serialization
  struct DomainConfigData
    include JSON::Serializable
    include YAML::Serializable

    property default_upstream : String
    property upstream_host_header : String = ""
    property preserve_original_host : Bool = false
    property verify_ssl : Bool = true
    property letsencrypt_enabled : Bool = false
    property letsencrypt_email : String? = nil
    property cert_file : String? = nil
    property key_file : String? = nil

    def initialize(
      @default_upstream : String,
      @upstream_host_header : String = "",
      @preserve_original_host : Bool = false,
      @verify_ssl : Bool = true,
      @letsencrypt_enabled : Bool = false,
      @letsencrypt_email : String? = nil,
      @cert_file : String? = nil,
      @key_file : String? = nil,
    )
    end
  end

  struct RateLimitConfigData
    include JSON::Serializable
    include YAML::Serializable

    property enabled : Bool = true
    property default_limit : Int32 = 100
    property window : String = "60s"
    property block_duration : String = "300s"

    def initialize(
      @enabled : Bool = true,
      @default_limit : Int32 = 100,
      @window : String = "60s",
      @block_duration : String = "300s",
    )
    end
  end

  struct GeoIPConfigData
    include JSON::Serializable
    include YAML::Serializable

    property enabled : Bool = false
    property mmdb_file : String? = nil
    property blocked_countries : Array(String) = [] of String
    property allowed_countries : Array(String) = [] of String

    def initialize(
      @enabled : Bool = false,
      @mmdb_file : String? = nil,
      @blocked_countries : Array(String) = [] of String,
      @allowed_countries : Array(String) = [] of String,
    )
    end
  end

  struct IPFilterConfigData
    include JSON::Serializable
    include YAML::Serializable

    property enabled : Bool = true
    property whitelist_file : String? = nil
    property blacklist_file : String? = nil

    def initialize(
      @enabled : Bool = true,
      @whitelist_file : String? = nil,
      @blacklist_file : String? = nil,
    )
    end
  end

  struct ServerConfigData
    include JSON::Serializable
    include YAML::Serializable

    property http_enabled : Bool = true
    property https_enabled : Bool = false
    property http_port : Int32 = 3030
    property https_port : Int32 = 3443

    def initialize(
      @http_enabled : Bool = true,
      @https_enabled : Bool = false,
      @http_port : Int32 = 3030,
      @https_port : Int32 = 3443,
    )
    end
  end

  # Full WAF config for API responses
  struct WAFConfigData
    include JSON::Serializable

    property mode : String = "enforce"
    property domains : Hash(String, DomainConfigData) = {} of String => DomainConfigData
    property rate_limiting : RateLimitConfigData = RateLimitConfigData.new
    property geoip : GeoIPConfigData = GeoIPConfigData.new
    property ip_filtering : IPFilterConfigData = IPFilterConfigData.new
    property server : ServerConfigData = ServerConfigData.new

    def initialize(
      @mode : String = "enforce",
      @domains : Hash(String, DomainConfigData) = {} of String => DomainConfigData,
      @rate_limiting : RateLimitConfigData = RateLimitConfigData.new,
      @geoip : GeoIPConfigData = GeoIPConfigData.new,
      @ip_filtering : IPFilterConfigData = IPFilterConfigData.new,
      @server : ServerConfigData = ServerConfigData.new,
    )
    end
  end

  class ConfigManager
    Log = ::Log.for("config_manager")

    getter waf_config_path : String
    @mutex : Mutex

    def initialize(@waf_config_path : String)
      @mutex = Mutex.new
    end

    # Read WAF config (always from file, no cache)
    def read_config : WAFConfigData
      @mutex.synchronize do
        unless File.exists?(@waf_config_path)
          Log.warn { "WAF config not found: #{@waf_config_path}" }
          return WAFConfigData.new
        end

        content = File.read(@waf_config_path)
        yaml = YAML.parse(content)
        waf_node = yaml["waf"]?

        unless waf_node
          Log.warn { "No 'waf' key in config" }
          return WAFConfigData.new
        end

        parse_waf_config(waf_node)
      end
    end

    private def parse_waf_config(node : YAML::Any) : WAFConfigData
      config = WAFConfigData.new

      config.mode = node["mode"]?.try(&.as_s) || "enforce"

      # Parse domains
      if domains_node = node["domains"]?
        domains_node.as_h.each do |domain, settings|
          domain_config = DomainConfigData.new(
            default_upstream: settings["default_upstream"].as_s,
            upstream_host_header: settings["upstream_host_header"]?.try(&.as_s) || "",
            preserve_original_host: settings["preserve_original_host"]?.try(&.as_bool) || false,
            verify_ssl: settings["verify_ssl"]?.try(&.as_bool) || true,
            letsencrypt_enabled: settings["letsencrypt_enabled"]?.try(&.as_bool) || false,
            letsencrypt_email: settings["letsencrypt_email"]?.try(&.as_s),
            cert_file: settings["cert_file"]?.try(&.as_s),
            key_file: settings["key_file"]?.try(&.as_s)
          )
          config.domains[domain.as_s] = domain_config
        end
      end

      # Parse rate limiting
      if rl_node = node["rate_limiting"]?
        config.rate_limiting = RateLimitConfigData.new(
          enabled: rl_node["enabled"]?.try(&.as_bool) || true,
          default_limit: rl_node["default_limit"]?.try(&.as_i) || 100,
          window: rl_node["window"]?.try(&.as_s) || "60s",
          block_duration: rl_node["block_duration"]?.try(&.as_s) || "300s"
        )
      end

      # Parse GeoIP
      if geo_node = node["geoip"]?
        config.geoip = GeoIPConfigData.new(
          enabled: geo_node["enabled"]?.try(&.as_bool) || false,
          mmdb_file: geo_node["mmdb_file"]?.try(&.as_s),
          blocked_countries: geo_node["blocked_countries"]?.try(&.as_a.map(&.as_s)) || [] of String,
          allowed_countries: geo_node["allowed_countries"]?.try(&.as_a.map(&.as_s)) || [] of String
        )
      end

      # Parse IP filtering
      if ip_node = node["ip_filtering"]?
        config.ip_filtering = IPFilterConfigData.new(
          enabled: ip_node["enabled"]?.try(&.as_bool) || true,
          whitelist_file: ip_node["whitelist_file"]?.try(&.as_s),
          blacklist_file: ip_node["blacklist_file"]?.try(&.as_s)
        )
      end

      # Parse server config
      if server_node = node["server"]?
        config.server = ServerConfigData.new(
          http_enabled: server_node["http_enabled"]?.try(&.as_bool) || true,
          https_enabled: server_node["https_enabled"]?.try(&.as_bool) || false,
          http_port: server_node["http_port"]?.try(&.as_i) || 3030,
          https_port: server_node["https_port"]?.try(&.as_i) || 3443
        )
      end

      config
    end

    # Get all domains
    def get_domains : Hash(String, DomainConfigData)
      read_config.domains
    end

    # Get single domain
    def get_domain(domain : String) : DomainConfigData?
      read_config.domains[domain]?
    end

    # Add or update domain
    def save_domain(domain : String, config : DomainConfigData) : Bool
      @mutex.synchronize do
        begin
          content = File.read(@waf_config_path)
          yaml = YAML.parse(content)

          # Build new YAML content
          new_content = build_yaml_with_domain(yaml, domain, config)

          # Backup current config
          backup_path = "#{@waf_config_path}.bak"
          File.copy(@waf_config_path, backup_path)

          # Write new config
          File.write(@waf_config_path, new_content)

          Log.info { "Domain saved: #{domain}" }
          true
        rescue ex
          Log.error { "Failed to save domain: #{ex.message}" }
          false
        end
      end
    end

    # Delete domain
    def delete_domain(domain : String) : Bool
      @mutex.synchronize do
        begin
          content = File.read(@waf_config_path)
          yaml = YAML.parse(content)

          new_content = build_yaml_without_domain(yaml, domain)

          # Backup current config
          backup_path = "#{@waf_config_path}.bak"
          File.copy(@waf_config_path, backup_path)

          # Write new config
          File.write(@waf_config_path, new_content)

          Log.info { "Domain deleted: #{domain}" }
          true
        rescue ex
          Log.error { "Failed to delete domain: #{ex.message}" }
          false
        end
      end
    end

    # Update global config
    def update_global_config(
      mode : String? = nil,
      rate_limiting : RateLimitConfigData? = nil,
      geoip : GeoIPConfigData? = nil,
      ip_filtering : IPFilterConfigData? = nil,
    ) : Bool
      @mutex.synchronize do
        begin
          content = File.read(@waf_config_path)
          yaml = YAML.parse(content)

          new_content = build_yaml_with_global_updates(yaml, mode, rate_limiting, geoip, ip_filtering)

          # Backup
          backup_path = "#{@waf_config_path}.bak"
          File.copy(@waf_config_path, backup_path)

          File.write(@waf_config_path, new_content)

          Log.info { "Global config updated" }
          true
        rescue ex
          Log.error { "Failed to update global config: #{ex.message}" }
          false
        end
      end
    end

    private def build_yaml_with_domain(yaml : YAML::Any, domain : String, config : DomainConfigData) : String
      # Read original file
      content = File.read(@waf_config_path)
      lines = content.lines

      result = String.build do |str|
        in_domains = false
        domain_written = false
        skip_current_domain = false
        domain_indent = 0
        i = 0

        while i < lines.size
          line = lines[i]
          stripped = line.strip

          # Domains section başlangıcı
          if stripped == "domains:"
            in_domains = true
            str << line << "\n"
            i += 1
            next
          end

          # Domains section içindeysek
          if in_domains
            # Boş satırları geç
            if stripped.empty?
              str << line << "\n"
              i += 1
              next
            end

            # Yeni top-level section başladı mı? (indent 2 veya daha az)
            line_indent = line.size - line.lstrip.size
            if line_indent <= 2 && stripped.ends_with?(":")
              # Domains section bitti
              unless domain_written
                str << build_domain_yaml(domain, config, 4)
                domain_written = true
              end
              in_domains = false
              str << line << "\n"
              i += 1
              next
            end

            # Bu bir domain tanımı mı? (indent 4, tırnak işareti ile başlar)
            if line_indent == 4 && (stripped.starts_with?("\"") || stripped.starts_with?("'"))
              # Bu bizim domain'imiz mi?
              if stripped.starts_with?("\"#{domain}\":") || stripped.starts_with?("'#{domain}':")
                # Bu domain'i skip et
                skip_current_domain = true
                domain_indent = line_indent
                i += 1
                next
              else
                # Başka bir domain
                if skip_current_domain
                  # Şimdi bizim domain'i yaz
                  str << build_domain_yaml(domain, config, 4)
                  domain_written = true
                  skip_current_domain = false
                end
                str << line << "\n"
                i += 1
                next
              end
            end

            # Skip edilen domain'in içeriğini atla
            if skip_current_domain && line_indent > domain_indent
              i += 1
              next
            elsif skip_current_domain && line_indent <= domain_indent
              # Domain bitti, bizim domain'i yaz
              str << build_domain_yaml(domain, config, 4)
              domain_written = true
              skip_current_domain = false
              # Bu satırı işle
              str << line << "\n"
              i += 1
              next
            end
          end

          str << line << "\n"
          i += 1
        end

        # Eğer hiç yazılmadıysa sona ekle
        unless domain_written
          str << "  domains:\n" unless in_domains
          str << build_domain_yaml(domain, config, 4)
        end
      end

      result
    end

    private def build_domain_yaml(domain : String, config : DomainConfigData, indent : Int32) : String
      pad = " " * indent
      String.build do |str|
        str << pad << "\"#{domain}\":\n"
        str << pad << "  default_upstream: \"#{config.default_upstream}\"\n"
        str << pad << "  upstream_host_header: \"#{config.upstream_host_header}\"\n" unless config.upstream_host_header.empty?
        str << pad << "  preserve_original_host: #{config.preserve_original_host}\n"
        str << pad << "  verify_ssl: #{config.verify_ssl}\n"
        if config.letsencrypt_enabled
          str << pad << "  letsencrypt_enabled: true\n"
          str << pad << "  letsencrypt_email: #{config.letsencrypt_email}\n" if config.letsencrypt_email
        end
        if config.cert_file
          str << pad << "  cert_file: #{config.cert_file}\n"
        end
        if config.key_file
          str << pad << "  key_file: #{config.key_file}\n"
        end
        str << "\n"
      end
    end

    private def build_yaml_without_domain(yaml : YAML::Any, domain_to_remove : String) : String
      content = File.read(@waf_config_path)
      lines = content.lines

      result = String.build do |str|
        skip_until_next_domain = false
        current_indent = 0

        lines.each do |line|
          # Check if this is the domain to remove
          if line.strip.starts_with?("\"#{domain_to_remove}\":") || line.strip.starts_with?("'#{domain_to_remove}':")
            skip_until_next_domain = true
            current_indent = line.size - line.lstrip.size
            next
          end

          if skip_until_next_domain
            line_indent = line.empty? ? current_indent + 1 : (line.size - line.lstrip.size)
            if line.strip.empty?
              next
            elsif line_indent <= current_indent
              skip_until_next_domain = false
              str << line << "\n"
            end
            next
          end

          str << line << "\n"
        end
      end

      result.chomp + "\n"
    end

    private def build_yaml_with_global_updates(
      yaml : YAML::Any,
      mode : String?,
      rate_limiting : RateLimitConfigData?,
      geoip : GeoIPConfigData?,
      ip_filtering : IPFilterConfigData?,
    ) : String
      # For simplicity, read and rewrite the entire config
      # In production, you'd want a more sophisticated YAML manipulation
      content = File.read(@waf_config_path)

      if mode
        content = content.gsub(/mode:\s*\w+/, "mode: #{mode}")
      end

      # For other sections, we'd need more complex YAML manipulation
      # This is a simplified version
      content
    end
  end
end
