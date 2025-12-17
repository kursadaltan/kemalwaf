require "kemal"
require "yaml"
require "json"
require "./database"
require "./auth"
require "./session"
require "./config_manager"
require "./rule_manager"
require "./api/auth_api"
require "./api/hosts_api"
require "./api/config_api"
require "./api/metrics_api"
require "./api/rules_api"
require "./middleware/auth_middleware"

module AdminPanel
  VERSION = "1.0.0"
  Log     = ::Log.for("admin")

  # Configuration
  struct AdminConfig
    include YAML::Serializable

    property port : Int32 = 8888
    property host : String = "0.0.0.0"
    property db_path : String = "data/admin.db"
    property session_ttl : String = "24h"
    property waf_config_path : String = "../config/waf.yml"
    property cookie_secure : Bool = false
    property cookie_same_site : String = "strict"

    def initialize(
      @port : Int32 = 8888,
      @host : String = "0.0.0.0",
      @db_path : String = "data/admin.db",
      @session_ttl : String = "24h",
      @waf_config_path : String = "../config/waf.yml",
      @cookie_secure : Bool = false,
      @cookie_same_site : String = "strict",
    )
    end
  end

  struct RootConfig
    include YAML::Serializable

    property admin : AdminConfig
  end

  class Application
    getter config : AdminConfig
    getter db : Database
    getter auth : Auth
    getter session_manager : SessionManager
    getter config_manager : ConfigManager
    getter rule_manager : RuleManager

    def initialize(config_path : String = "config/admin.yml")
      @config = load_config(config_path)
      @db = Database.new(@config.db_path)
      @auth = Auth.new(@db)
      @session_manager = SessionManager.new(@db, parse_duration(@config.session_ttl))
      @config_manager = ConfigManager.new(@config.waf_config_path)
      @rule_manager = RuleManager.new(get_rules_dir)

      setup_middleware
      setup_routes
      setup_static_files
      start_background_tasks
    end

    private def load_config(path : String) : AdminConfig
      if File.exists?(path)
        content = File.read(path)
        RootConfig.from_yaml(content).admin
      else
        Log.warn { "Config file not found: #{path}, using defaults" }
        AdminConfig.new
      end
    end

    private def get_rules_dir : String
      # Log current working directory and config path
      cwd = Dir.current
      Log.info { "Admin panel working directory: #{cwd}" }
      Log.info { "WAF config path: #{@config.waf_config_path}" }

      # Try to read rules directory from waf.yml
      if File.exists?(@config.waf_config_path)
        begin
          expanded_config_path = File.expand_path(@config.waf_config_path)
          Log.info { "WAF config absolute path: #{expanded_config_path}" }

          content = File.read(@config.waf_config_path)
          yaml = YAML.parse(content)
          if waf_node = yaml["waf"]?
            if rules_node = waf_node["rules"]?
              if dir = rules_node["directory"]?.try(&.as_s)
                Log.info { "Rules directory from waf.yml: #{dir}" }

                # Resolve relative path from waf config location
                waf_dir = File.dirname(expanded_config_path)
                expanded = File.expand_path(dir, waf_dir)

                Log.info { "Calculated rules directory: #{expanded} (from waf_dir=#{waf_dir}, dir=#{dir})" }

                # Verify directory exists, if not try alternative paths
                if Dir.exists?(expanded)
                  Log.info { "✓ Rules directory found: #{expanded}" }
                  return expanded
                else
                  Log.warn { "✗ Rules directory does not exist: #{expanded}, trying alternatives..." }
                  # Try ../rules relative to config
                  alt_path = File.expand_path("../rules", waf_dir)
                  Log.info { "Trying alternative path: #{alt_path}" }
                  if Dir.exists?(alt_path)
                    Log.info { "✓ Using alternative rules directory: #{alt_path}" }
                    return alt_path
                  end
                  # Try rules/ relative to project root
                  project_root = File.expand_path("../..", waf_dir)
                  root_rules = File.join(project_root, "rules")
                  Log.info { "Trying project root rules: #{root_rules}" }
                  if Dir.exists?(root_rules)
                    Log.info { "✓ Using project root rules directory: #{root_rules}" }
                    return root_rules
                  end
                end
              end
            end
          end
        rescue ex
          Log.error { "Failed to read rules directory from config: #{ex.message}" }
          Log.error { ex.backtrace.join("\n") if ex.backtrace }
          # Fall through to default
        end
      else
        Log.warn { "WAF config file does not exist: #{@config.waf_config_path}" }
      end

      # Default to ../rules relative to config file
      if File.exists?(@config.waf_config_path)
        default_dir = File.expand_path("../rules", File.dirname(File.expand_path(@config.waf_config_path)))
      else
        # Fallback: try ../rules from admin directory
        default_dir = File.expand_path("../rules", cwd)
      end
      Log.info { "Using default rules directory: #{default_dir}" }
      default_dir
    end

    private def parse_duration(duration : String) : Time::Span
      case duration
      when /^(\d+)h$/
        $1.to_i.hours
      when /^(\d+)m$/
        $1.to_i.minutes
      when /^(\d+)s$/
        $1.to_i.seconds
      when /^(\d+)d$/
        $1.to_i.days
      else
        24.hours
      end
    end

    private def setup_middleware
      # Add auth middleware
      add_handler AuthMiddleware.new(self)
    end

    private def setup_routes
      # CORS for development
      before_all do |env|
        origin = env.request.headers["Origin"]? || "http://localhost:5173"
        env.response.headers["Access-Control-Allow-Origin"] = origin
        env.response.headers["Access-Control-Allow-Credentials"] = "true"
        env.response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        env.response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, Cookie"
        env.response.headers["Access-Control-Max-Age"] = "86400"
      end

      # Handle preflight OPTIONS requests
      options "/*" do |env|
        env.response.status_code = 204
        ""
      end

      # Setup API routes
      AuthAPI.setup(self)
      HostsAPI.setup(self)
      ConfigAPI.setup(self)
      MetricsAPI.setup(self)
      RulesAPI.setup(self)

      # Health check
      get "/api/health" do |env|
        env.response.content_type = "application/json"
        {status: "ok", version: VERSION}.to_json
      end

      # Error handlers
      error 401 do |env|
        env.response.content_type = "application/json"
        {error: "Unauthorized"}.to_json
      end

      error 403 do |env|
        env.response.content_type = "application/json"
        {error: "Forbidden"}.to_json
      end

      error 404 do |env|
        # For API routes, return JSON 404
        if env.request.path.starts_with?("/api/")
          env.response.content_type = "application/json"
          next({error: "Not found"}.to_json)
        end

        # For non-API routes, serve index.html for SPA routing
        index_path = "public/index.html"
        if File.exists?(index_path)
          env.response.status_code = 200
          send_file env, index_path, "text/html"
        else
          env.response.content_type = "text/html"
          <<-HTML
          <!DOCTYPE html>
          <html>
          <head>
            <title>Kemal WAF Admin</title>
            <style>
              body { font-family: system-ui; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #0f172a; color: #fff; }
              .container { text-align: center; }
              h1 { font-size: 2rem; margin-bottom: 1rem; }
              p { color: #94a3b8; }
            </style>
          </head>
          <body>
            <div class="container">
              <h1>🛡️ Kemal WAF Admin</h1>
              <p>Frontend not built yet. Run: <code>cd admin-ui && npm run build</code></p>
            </div>
          </body>
          </html>
          HTML
        end
      end

      error 500 do |env, ex|
        Log.error { "Internal error: #{ex.message}" }
        env.response.content_type = "application/json"
        {error: "Internal server error"}.to_json
      end
    end

    private def setup_static_files
      # Enable static file serving
      serve_static({"gzip" => true})

      # Set public folder
      public_folder "public"
    end

    private def start_background_tasks
      # Cleanup expired sessions every hour
      spawn do
        loop do
          sleep 1.hour
          @db.cleanup_expired_sessions
        end
      end
    end

    def run
      Log.info { "Starting Kemal WAF Admin Panel v#{VERSION}" }
      Log.info { "Listening on http://#{@config.host}:#{@config.port}" }
      Log.info { "Setup required: #{@db.setup_required?}" }

      Kemal.config.host_binding = @config.host
      Kemal.config.port = @config.port
      Kemal.config.env = "production"
      Kemal.config.logging = false

      Kemal.run
    end
  end
end

# Main entry point
config_path = ENV.fetch("ADMIN_CONFIG", "config/admin.yml")
app = AdminPanel::Application.new(config_path)
app.run
