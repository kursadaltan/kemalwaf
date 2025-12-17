require "json"

module AdminPanel
  module RulesAPI
    def self.setup(app : Application)
      # List all rules
      get "/api/rules" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        rules = app.rule_manager.get_rules

        # Optional filtering
        if category = env.params.query["category"]?
          rules = rules.select { |r| r.category == category }
        end

        if severity = env.params.query["severity"]?
          rules = rules.select { |r| r.severity == severity }
        end

        {
          rules:      rules,
          total:      rules.size,
          categories: app.rule_manager.get_categories,
        }.to_json
      end

      # Get single rule
      get "/api/rules/:id" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        id = env.params.url["id"].to_i
        rule = app.rule_manager.get_rule(id)

        unless rule
          env.response.status_code = 404
          next {error: "Rule not found"}.to_json
        end

        rule.to_json
      end

      # Create new rule
      post "/api/rules" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        begin
          body = env.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          id = data["id"]?.try(&.as_i)
          msg = data["msg"]?.try(&.as_s) || ""
          action = data["action"]?.try(&.as_s) || "deny"

          unless id
            env.response.status_code = 400
            next {error: "Rule ID is required"}.to_json
          end

          # Check if rule already exists
          if app.rule_manager.get_rule(id)
            env.response.status_code = 409
            next {error: "Rule with this ID already exists"}.to_json
          end

          # Parse variables
          variables = parse_variables(data["variables"]?)

          rule = RuleData.new(
            id: id,
            msg: msg,
            action: action,
            name: data["name"]?.try(&.as_s),
            pattern: data["pattern"]?.try(&.as_s),
            operator: data["operator"]?.try(&.as_s) || "regex",
            severity: data["severity"]?.try(&.as_s),
            category: data["category"]?.try(&.as_s),
            paranoia_level: data["paranoia_level"]?.try(&.as_i),
            tags: data["tags"]?.try(&.as_a.map(&.as_s)),
            transforms: data["transforms"]?.try(&.as_a.map(&.as_s)),
            variables: variables,
            score: data["score"]?.try(&.as_i),
            default_score: data["default_score"]?.try(&.as_i) || 1
          )

          target_file = data["target_file"]?.try(&.as_s)

          unless app.rule_manager.create_rule(rule, target_file)
            env.response.status_code = 500
            next {error: "Failed to create rule"}.to_json
          end

          # Audit log
          app.db.log_audit(
            user.id,
            "rule_created",
            "Rule ID: #{id}, Msg: #{msg}",
            env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
          )

          env.response.status_code = 201
          {
            success: true,
            message: "Rule created",
            id:      id,
          }.to_json
        rescue ex : JSON::ParseException
          env.response.status_code = 400
          {error: "Invalid JSON"}.to_json
        end
      end

      # Update rule
      put "/api/rules/:id" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        id = env.params.url["id"].to_i

        unless app.rule_manager.get_rule(id)
          env.response.status_code = 404
          next {error: "Rule not found"}.to_json
        end

        begin
          body = env.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          msg = data["msg"]?.try(&.as_s) || ""
          action = data["action"]?.try(&.as_s) || "deny"

          # Parse variables
          variables = parse_variables(data["variables"]?)

          rule = RuleData.new(
            id: id,
            msg: msg,
            action: action,
            name: data["name"]?.try(&.as_s),
            pattern: data["pattern"]?.try(&.as_s),
            operator: data["operator"]?.try(&.as_s) || "regex",
            severity: data["severity"]?.try(&.as_s),
            category: data["category"]?.try(&.as_s),
            paranoia_level: data["paranoia_level"]?.try(&.as_i),
            tags: data["tags"]?.try(&.as_a.map(&.as_s)),
            transforms: data["transforms"]?.try(&.as_a.map(&.as_s)),
            variables: variables,
            score: data["score"]?.try(&.as_i),
            default_score: data["default_score"]?.try(&.as_i) || 1
          )

          unless app.rule_manager.update_rule(id, rule)
            env.response.status_code = 500
            next {error: "Failed to update rule"}.to_json
          end

          # Audit log
          app.db.log_audit(
            user.id,
            "rule_updated",
            "Rule ID: #{id}",
            env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
          )

          {
            success: true,
            message: "Rule updated",
          }.to_json
        rescue ex : JSON::ParseException
          env.response.status_code = 400
          {error: "Invalid JSON"}.to_json
        end
      end

      # Delete rule
      delete "/api/rules/:id" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        id = env.params.url["id"].to_i

        unless app.rule_manager.get_rule(id)
          env.response.status_code = 404
          next {error: "Rule not found"}.to_json
        end

        unless app.rule_manager.delete_rule(id)
          env.response.status_code = 500
          next {error: "Failed to delete rule"}.to_json
        end

        # Audit log
        app.db.log_audit(
          user.id,
          "rule_deleted",
          "Rule ID: #{id}",
          env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
        )

        {
          success: true,
          message: "Rule deleted",
        }.to_json
      end

      # Reload rules from disk
      post "/api/rules/reload" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        rules = app.rule_manager.reload

        # Audit log
        app.db.log_audit(
          user.id,
          "rules_reloaded",
          "Loaded #{rules.size} rules",
          env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
        )

        {
          success: true,
          message: "Rules reloaded",
          count:   rules.size,
        }.to_json
      end

      # Get rules by file
      get "/api/rules/files" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        files = app.rule_manager.get_rules_by_file

        files_data = files.map do |file, rules|
          {
            file:  file,
            count: rules.size,
            rules: rules.map(&.id),
          }
        end

        {files: files_data}.to_json
      end

      # Get domain WAF configuration
      get "/api/rules/domains/:domain" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        domain = URI.decode(env.params.url["domain"])
        domain_config = app.config_manager.get_domain(domain)

        unless domain_config
          env.response.status_code = 404
          next {error: "Domain not found"}.to_json
        end

        # Get WAF configuration from domain
        all_rules = app.rule_manager.get_rules

        # Parse waf_rules from domain config if available
        waf_config = get_domain_waf_config(app, domain)

        {
          domain:         domain,
          threshold:      waf_config[:threshold],
          enabled_rules:  waf_config[:enabled],
          disabled_rules: waf_config[:disabled],
          all_rules:      all_rules.map { |r| {id: r.id, name: r.name || r.msg, category: r.category, score: r.effective_score} },
        }.to_json
      end

      # Update domain WAF configuration
      put "/api/rules/domains/:domain" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        domain = URI.decode(env.params.url["domain"])

        unless app.config_manager.get_domain(domain)
          env.response.status_code = 404
          next {error: "Domain not found"}.to_json
        end

        begin
          body = env.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          threshold = data["threshold"]?.try(&.as_i) || 5
          enabled = data["enabled_rules"]?.try(&.as_a.map(&.as_i)) || [] of Int32
          disabled = data["disabled_rules"]?.try(&.as_a.map(&.as_i)) || [] of Int32

          unless app.config_manager.update_domain_waf_config(domain, threshold, enabled, disabled)
            env.response.status_code = 500
            next {error: "Failed to update domain WAF configuration"}.to_json
          end

          # Audit log
          app.db.log_audit(
            user.id,
            "domain_waf_updated",
            "Domain: #{domain}, Threshold: #{threshold}",
            env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
          )

          {
            success: true,
            message: "Domain WAF configuration updated",
          }.to_json
        rescue ex : JSON::ParseException
          env.response.status_code = 400
          {error: "Invalid JSON"}.to_json
        end
      end

      # Get domain threshold
      get "/api/rules/domains/:domain/threshold" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        domain = URI.decode(env.params.url["domain"])

        unless app.config_manager.get_domain(domain)
          env.response.status_code = 404
          next {error: "Domain not found"}.to_json
        end

        waf_config = get_domain_waf_config(app, domain)

        {
          domain:    domain,
          threshold: waf_config[:threshold],
        }.to_json
      end

      # Update domain threshold
      put "/api/rules/domains/:domain/threshold" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        domain = URI.decode(env.params.url["domain"])

        unless app.config_manager.get_domain(domain)
          env.response.status_code = 404
          next {error: "Domain not found"}.to_json
        end

        begin
          body = env.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          threshold = data["threshold"]?.try(&.as_i)

          unless threshold
            env.response.status_code = 400
            next {error: "Threshold is required"}.to_json
          end

          # Get current config and update threshold only
          waf_config = get_domain_waf_config(app, domain)

          unless app.config_manager.update_domain_waf_config(domain, threshold, waf_config[:enabled], waf_config[:disabled])
            env.response.status_code = 500
            next {error: "Failed to update threshold"}.to_json
          end

          # Audit log
          app.db.log_audit(
            user.id,
            "domain_threshold_updated",
            "Domain: #{domain}, Threshold: #{threshold}",
            env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
          )

          {
            success: true,
            message: "Threshold updated",
          }.to_json
        rescue ex : JSON::ParseException
          env.response.status_code = 400
          {error: "Invalid JSON"}.to_json
        end
      end
    end

    private def self.parse_variables(node : JSON::Any?) : Array(VariableSpecData)?
      return nil unless node

      result = [] of VariableSpecData
      node.as_a.each do |item|
        if item.as_s?
          result << VariableSpecData.new(item.as_s)
        elsif item.as_h?
          type = item["type"]?.try(&.as_s) || ""
          names = item["names"]?.try(&.as_a.map(&.as_s))
          result << VariableSpecData.new(type, names)
        end
      end
      result
    rescue
      nil
    end

    private def self.get_domain_waf_config(app : Application, domain : String) : NamedTuple(threshold: Int32, enabled: Array(Int32), disabled: Array(Int32))
      # Read from config file directly to get latest values
      config = app.config_manager.read_config
      domain_config = config.domains[domain]?

      if domain_config
        # Try to get waf_threshold and waf_rules from raw YAML
        content = File.read(app.config_manager.waf_config_path)
        yaml = YAML.parse(content)
        waf_node = yaml["waf"]?

        if waf_node && (domains_node = waf_node["domains"]?)
          if domain_settings = domains_node[domain]?
            threshold = domain_settings["waf_threshold"]?.try(&.as_i) || 5

            enabled = [] of Int32
            disabled = [] of Int32

            if waf_rules = domain_settings["waf_rules"]?
              if enabled_node = waf_rules["enabled"]?
                enabled = enabled_node.as_a.map(&.as_i)
              end
              if disabled_node = waf_rules["disabled"]?
                disabled = disabled_node.as_a.map(&.as_i)
              end
            end

            return {threshold: threshold, enabled: enabled, disabled: disabled}
          end
        end
      end

      {threshold: 5, enabled: [] of Int32, disabled: [] of Int32}
    end
  end
end
