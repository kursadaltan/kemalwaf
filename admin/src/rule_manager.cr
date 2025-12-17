require "yaml"
require "json"
require "file_utils"

module AdminPanel
  # Rule data structure for JSON serialization
  struct RuleData
    include JSON::Serializable
    include YAML::Serializable

    property id : Int32
    property name : String?
    property msg : String
    property pattern : String?
    property action : String
    property operator : String?
    property severity : String?
    property category : String?
    property paranoia_level : Int32?
    property tags : Array(String)?
    property transforms : Array(String)?
    property variables : Array(VariableSpecData)?
    property score : Int32?           # Custom score (optional)
    property default_score : Int32 = 1 # Default score

    # Source file (set after loading, not serialized to YAML)
    @[JSON::Field(key: "source_file")]
    @[YAML::Field(ignore: true)]
    property source_file : String?

    def initialize(
      @id : Int32,
      @msg : String,
      @action : String,
      @name : String? = nil,
      @pattern : String? = nil,
      @operator : String? = nil,
      @severity : String? = nil,
      @category : String? = nil,
      @paranoia_level : Int32? = nil,
      @tags : Array(String)? = nil,
      @transforms : Array(String)? = nil,
      @variables : Array(VariableSpecData)? = nil,
      @score : Int32? = nil,
      @default_score : Int32 = 1,
      @source_file : String? = nil,
    )
    end

    def effective_score : Int32
      @score || @default_score
    end
  end

  struct VariableSpecData
    include JSON::Serializable
    include YAML::Serializable

    property type : String
    property names : Array(String)?

    def initialize(@type : String, @names : Array(String)? = nil)
    end
  end

  # Domain WAF Rules Configuration
  struct DomainWAFRulesData
    include JSON::Serializable
    include YAML::Serializable

    property enabled : Array(Int32) = [] of Int32
    property disabled : Array(Int32) = [] of Int32

    def initialize(
      @enabled : Array(Int32) = [] of Int32,
      @disabled : Array(Int32) = [] of Int32,
    )
    end
  end

  # Domain WAF Configuration
  struct DomainWAFConfigData
    include JSON::Serializable

    property threshold : Int32 = 5
    property rules : DomainWAFRulesData?

    def initialize(
      @threshold : Int32 = 5,
      @rules : DomainWAFRulesData? = nil,
    )
    end
  end

  class RuleManager
    Log = ::Log.for("rule_manager")

    getter rules_dir : String
    @mutex : Mutex
    @rules_cache : Array(RuleData)?
    @cache_mtime : Time?

    def initialize(@rules_dir : String = "rules")
      @mutex = Mutex.new
      @rules_cache = nil
      @cache_mtime = nil
      
      # Log rules directory and verify it exists
      expanded_dir = File.expand_path(@rules_dir)
      Log.info { "RuleManager initialized with rules directory: #{expanded_dir}" }
      
      unless Dir.exists?(expanded_dir)
        Log.warn { "Rules directory does not exist: #{expanded_dir}" }
      else
        # Count YAML files
        yaml_files = Dir.glob(File.join(expanded_dir, "**", "*.yaml"))
        Log.info { "Found #{yaml_files.size} YAML files in rules directory" }
      end
    end

    # Load all rules from YAML files
    def load_rules : Array(RuleData)
      @mutex.synchronize do
        rules = [] of RuleData
        expanded_dir = File.expand_path(@rules_dir)
        
        Log.info { "Loading rules from directory: #{expanded_dir}" }
        
        unless Dir.exists?(expanded_dir)
          Log.error { "Rules directory does not exist: #{expanded_dir}" }
          @rules_cache = rules
          return rules
        end

        yaml_files = Dir.glob(File.join(expanded_dir, "**", "*.yaml"))
        Log.info { "Found #{yaml_files.size} YAML files to process" }

        yaml_files.each do |file_path|
          begin
            content = File.read(file_path)
            yaml_data = YAML.parse(content)

            unless yaml_data.raw.is_a?(Hash) && yaml_data["rules"]?
              Log.debug { "Skipping #{file_path}: no 'rules' key or not a Hash" }
              next
            end
            
            rules_node = yaml_data["rules"]
            unless rules_node.raw.is_a?(Array)
              Log.debug { "Skipping #{file_path}: 'rules' is not an Array" }
              next
            end

            file_rule_count = 0
            rules_node.as_a.each do |rule_node|
              rule = parse_rule(rule_node, file_path)
              if rule
                rules << rule
                file_rule_count += 1
              end
            end
            Log.debug { "Loaded #{file_rule_count} rules from #{file_path}" }
          rescue ex
            Log.warn { "Failed to load rules from #{file_path}: #{ex.message}" }
            Log.debug { ex.backtrace.join("\n") if ex.backtrace }
          end
        end

        @rules_cache = rules
        Log.info { "Total #{rules.size} rules loaded from #{yaml_files.size} files" }
        rules
      end
    end

    # Get all rules (cached)
    def get_rules : Array(RuleData)
      if cached = @rules_cache
        Log.debug { "Returning #{cached.size} rules from cache" }
        cached
      else
        Log.debug { "Cache empty, loading rules..." }
        load_rules
      end
    end

    # Get rule by ID
    def get_rule(id : Int32) : RuleData?
      get_rules.find { |r| r.id == id }
    end

    # Create a new rule
    def create_rule(rule : RuleData, target_file : String? = nil) : Bool
      @mutex.synchronize do
        begin
          # Determine target file
          file_path = target_file || File.join(@rules_dir, "custom-rules.yaml")
          
          # Ensure directory exists
          FileUtils.mkdir_p(File.dirname(file_path))

          # Read existing content or create new
          existing_rules = [] of YAML::Any
          if File.exists?(file_path)
            content = File.read(file_path)
            yaml_data = YAML.parse(content)
            if yaml_data["rules"]?
              existing_rules = yaml_data["rules"].as_a
            end
          end

          # Check for duplicate ID
          if existing_rules.any? { |r| r["id"]?.try(&.as_i) == rule.id }
            Log.error { "Rule with ID #{rule.id} already exists" }
            return false
          end

          # Add new rule
          new_rule_yaml = build_rule_yaml(rule)
          
          # Write to file
          write_rules_file(file_path, existing_rules, new_rule_yaml)

          # Clear cache
          @rules_cache = nil
          Log.info { "Rule created: ID=#{rule.id}, File=#{file_path}" }
          true
        rescue ex
          Log.error { "Failed to create rule: #{ex.message}" }
          false
        end
      end
    end

    # Update an existing rule
    def update_rule(id : Int32, rule : RuleData) : Bool
      @mutex.synchronize do
        begin
          # Find existing rule to get source file
          existing = get_rule(id)
          unless existing
            Log.error { "Rule not found: #{id}" }
            return false
          end

          source_file = existing.source_file
          unless source_file && File.exists?(source_file)
            Log.error { "Source file not found for rule #{id}" }
            return false
          end

          # Read and update the file
          content = File.read(source_file)
          yaml_data = YAML.parse(content)
          
          rules_array = yaml_data["rules"]?.try(&.as_a) || ([] of YAML::Any)
          updated = false

          new_rules = rules_array.map do |r|
            if r["id"]?.try(&.as_i) == id
              updated = true
              build_rule_yaml_any(rule)
            else
              r
            end
          end

          if updated
            write_rules_file_from_any(source_file, new_rules)
            @rules_cache = nil
            Log.info { "Rule updated: ID=#{id}" }
            true
          else
            Log.error { "Rule #{id} not found in file" }
            false
          end
        rescue ex
          Log.error { "Failed to update rule: #{ex.message}" }
          false
        end
      end
    end

    # Delete a rule
    def delete_rule(id : Int32) : Bool
      @mutex.synchronize do
        begin
          # Find existing rule to get source file
          existing = get_rule(id)
          unless existing
            Log.error { "Rule not found: #{id}" }
            return false
          end

          source_file = existing.source_file
          unless source_file && File.exists?(source_file)
            Log.error { "Source file not found for rule #{id}" }
            return false
          end

          # Read and update the file
          content = File.read(source_file)
          yaml_data = YAML.parse(content)
          
          rules_array = yaml_data["rules"]?.try(&.as_a) || ([] of YAML::Any)
          new_rules = rules_array.reject { |r| r["id"]?.try(&.as_i) == id }

          if new_rules.size < rules_array.size
            write_rules_file_from_any(source_file, new_rules)
            @rules_cache = nil
            Log.info { "Rule deleted: ID=#{id}" }
            true
          else
            Log.error { "Rule #{id} not found in file" }
            false
          end
        rescue ex
          Log.error { "Failed to delete rule: #{ex.message}" }
          false
        end
      end
    end

    # Get rules grouped by file
    def get_rules_by_file : Hash(String, Array(RuleData))
      result = {} of String => Array(RuleData)
      get_rules.each do |rule|
        file = rule.source_file || "unknown"
        result[file] ||= [] of RuleData
        result[file] << rule
      end
      result
    end

    # Get rule categories
    def get_categories : Array(String)
      get_rules.map(&.category).compact.uniq.sort
    end

    # Get rules by category
    def get_rules_by_category(category : String) : Array(RuleData)
      get_rules.select { |r| r.category == category }
    end

    # Reload rules from disk
    def reload : Array(RuleData)
      @rules_cache = nil
      load_rules
    end

    private def parse_rule(node : YAML::Any, source_file : String) : RuleData?
      begin
        id = node["id"]?.try(&.as_i)
        unless id
          Log.debug { "Skipping rule in #{source_file}: missing or invalid 'id' field" }
          return nil
        end

        msg = node["msg"]?.try(&.as_s) || ""
        action = node["action"]?.try(&.as_s) || "deny"

        variables = parse_variables(node["variables"]?)

        # Helper to safely extract string values (handles null)
        safe_string = ->(key : String) { 
          val = node[key]?
          return nil unless val
          val.nil? ? nil : val.as_s?
        }
        
        # Helper to safely extract array values
        safe_array = ->(key : String) {
          val = node[key]?
          return nil unless val
          return nil if val.nil?
          arr = val.as_a?
          return nil unless arr
          arr.map(&.as_s)
        }

        rule = RuleData.new(
          id: id,
          msg: msg,
          action: action,
          name: safe_string.call("name"),
          pattern: safe_string.call("pattern"),
          operator: safe_string.call("operator"),
          severity: safe_string.call("severity"),
          category: safe_string.call("category"),
          paranoia_level: node["paranoia_level"]?.try(&.as_i),
          tags: safe_array.call("tags"),
          transforms: safe_array.call("transforms"),
          variables: variables,
          score: node["score"]?.try(&.as_i),
          default_score: node["default_score"]?.try(&.as_i) || 1,
          source_file: source_file
        )
        
        Log.debug { "Parsed rule ID=#{id} from #{source_file}" }
        rule
      rescue ex
        rule_id = node["id"]?.try(&.as_i) || "unknown"
        Log.warn { "Failed to parse rule ID=#{rule_id} from #{source_file}: #{ex.message}" }
        Log.debug { ex.backtrace.join("\n") if ex.backtrace }
        nil
      end
    end

    private def parse_variables(node : YAML::Any?) : Array(VariableSpecData)?
      return nil unless node

      result = [] of VariableSpecData
      node.as_a.each do |item|
        case item.raw
        when String
          result << VariableSpecData.new(item.as_s)
        when Hash
          type = item["type"]?.try(&.as_s) || ""
          names = item["names"]?.try(&.as_a.map(&.as_s))
          result << VariableSpecData.new(type, names)
        end
      end
      result
    rescue
      nil
    end

    private def build_rule_yaml(rule : RuleData) : String
      String.build do |str|
        str << "  - id: #{rule.id}\n"
        str << "    name: \"#{escape_yaml(rule.name.to_s)}\"\n" if rule.name
        str << "    msg: \"#{escape_yaml(rule.msg)}\"\n"
        str << "    category: \"#{escape_yaml(rule.category.to_s)}\"\n" if rule.category
        str << "    severity: \"#{escape_yaml(rule.severity.to_s)}\"\n" if rule.severity
        str << "    paranoia_level: #{rule.paranoia_level}\n" if rule.paranoia_level
        str << "    operator: \"#{escape_yaml(rule.operator.to_s)}\"\n" if rule.operator
        str << "    pattern: \"#{escape_yaml(rule.pattern.to_s)}\"\n" if rule.pattern
        str << "    action: \"#{escape_yaml(rule.action)}\"\n"
        str << "    score: #{rule.score}\n" if rule.score
        str << "    default_score: #{rule.default_score}\n" if rule.default_score != 1
        
        if vars = rule.variables
          str << "    variables:\n"
          vars.each do |v|
            if v.names
              str << "      - type: #{v.type}\n"
              str << "        names:\n"
              v.names.try &.each { |n| str << "          - #{n}\n" }
            else
              str << "      - type: #{v.type}\n"
            end
          end
        end

        if transforms = rule.transforms
          str << "    transforms:\n"
          transforms.each { |t| str << "      - #{t}\n" }
        end

        if tags = rule.tags
          str << "    tags:\n"
          tags.each { |t| str << "      - \"#{escape_yaml(t)}\"\n" }
        end
      end
    end

    private def build_rule_yaml_any(rule : RuleData) : YAML::Any
      hash = {} of YAML::Any => YAML::Any
      hash[YAML::Any.new("id")] = YAML::Any.new(rule.id.to_i64)
      hash[YAML::Any.new("name")] = YAML::Any.new(rule.name.to_s) if rule.name
      hash[YAML::Any.new("msg")] = YAML::Any.new(rule.msg)
      hash[YAML::Any.new("category")] = YAML::Any.new(rule.category.to_s) if rule.category
      hash[YAML::Any.new("severity")] = YAML::Any.new(rule.severity.to_s) if rule.severity
      hash[YAML::Any.new("paranoia_level")] = YAML::Any.new(rule.paranoia_level.not_nil!.to_i64) if rule.paranoia_level
      hash[YAML::Any.new("operator")] = YAML::Any.new(rule.operator.to_s) if rule.operator
      hash[YAML::Any.new("pattern")] = YAML::Any.new(rule.pattern.to_s) if rule.pattern
      hash[YAML::Any.new("action")] = YAML::Any.new(rule.action)
      hash[YAML::Any.new("score")] = YAML::Any.new(rule.score.not_nil!.to_i64) if rule.score
      hash[YAML::Any.new("default_score")] = YAML::Any.new(rule.default_score.to_i64) if rule.default_score != 1

      if vars = rule.variables
        vars_array = vars.map do |v|
          if v.names
            var_hash = {} of YAML::Any => YAML::Any
            var_hash[YAML::Any.new("type")] = YAML::Any.new(v.type)
            var_hash[YAML::Any.new("names")] = YAML::Any.new(v.names.not_nil!.map { |n| YAML::Any.new(n) })
            YAML::Any.new(var_hash)
          else
            var_hash = {} of YAML::Any => YAML::Any
            var_hash[YAML::Any.new("type")] = YAML::Any.new(v.type)
            YAML::Any.new(var_hash)
          end
        end
        hash[YAML::Any.new("variables")] = YAML::Any.new(vars_array)
      end

      if transforms = rule.transforms
        hash[YAML::Any.new("transforms")] = YAML::Any.new(transforms.map { |t| YAML::Any.new(t) })
      end

      if tags = rule.tags
        hash[YAML::Any.new("tags")] = YAML::Any.new(tags.map { |t| YAML::Any.new(t) })
      end

      YAML::Any.new(hash)
    end

    private def write_rules_file(file_path : String, existing_rules : Array(YAML::Any), new_rule_yaml : String)
      File.open(file_path, "w") do |file|
        file << "---\n"
        file << "rules:\n"
        
        existing_rules.each do |rule|
          file << rule.to_yaml.gsub(/^---\n/, "").gsub(/^/, "  ")
        end
        
        file << new_rule_yaml
      end
    end

    private def write_rules_file_from_any(file_path : String, rules : Array(YAML::Any))
      root_hash = {} of YAML::Any => YAML::Any
      root_hash[YAML::Any.new("rules")] = YAML::Any.new(rules)
      
      File.write(file_path, YAML::Any.new(root_hash).to_yaml)
    end

    private def escape_yaml(str : String) : String
      str.gsub("\\", "\\\\").gsub("\"", "\\\"")
    end
  end
end
