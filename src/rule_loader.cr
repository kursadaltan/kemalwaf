require "yaml"
require "file"

module KemalWAF
  # Variable yapısı (esnek variable tanımlama için)
  struct VariableSpec
    include YAML::Serializable

    property type : String
    property names : Array(String)?

    def initialize(@type : String, @names : Array(String)? = nil)
    end
  end

  # Variables için özel converter - hem String hem VariableSpec array'i destekler
  module VariableConverter
    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Array(VariableSpec)
      result = [] of VariableSpec

      case node
      when YAML::Nodes::Sequence
        node.nodes.each do |item|
          case item
          when YAML::Nodes::Scalar
            # String formatı: "ARGS" (eski format - backward compatibility)
            result << VariableSpec.new(item.value)
          when YAML::Nodes::Mapping
            # Mapping format: {type: "HEADERS", names: [...]} (new format)
            type_val = ""
            names_val = nil

            item.nodes.each_slice(2) do |pair|
              key_node = pair[0]
              value_node = pair[1]?
              if key_node.is_a?(YAML::Nodes::Scalar) && key_node.value == "type"
                type_val = value_node.as(YAML::Nodes::Scalar).value if value_node.is_a?(YAML::Nodes::Scalar)
              elsif key_node.is_a?(YAML::Nodes::Scalar) && key_node.value == "names"
                if value_node.is_a?(YAML::Nodes::Sequence)
                  names_val = value_node.nodes.map do |n|
                    n.as(YAML::Nodes::Scalar).value if n.is_a?(YAML::Nodes::Scalar)
                  end.compact
                end
              end
            end

            result << VariableSpec.new(type_val, names_val)
          end
        end
      end

      result
    end
  end

  # Rule structure
  struct Rule
    include YAML::Serializable

    property id : Int32
    property msg : String

    @[YAML::Field(converter: KemalWAF::VariableConverter)]
    property variables : Array(VariableSpec)

    property pattern : String?
    property action : String
    property transforms : Array(String)?
    property operator : String?
    property paranoia_level : Int32?
    property severity : String?
    property category : String?
    property tags : Array(String)?
    property name : String?

    @[YAML::Field(ignore: true)]
    property compiled_regex : Regex?

    # Variable spec'leri al
    def variable_specs : Array(VariableSpec)
      @variables
    end

    def initialize(@id, @msg, @variables : Array(VariableSpec), @pattern, @action, @transforms, @operator, @paranoia_level, @severity, @category, @tags, @name)
      @compiled_regex = nil
      compile_pattern
    end

    def compile_pattern
      # Only compile pattern for regex operator
      op = @operator || "regex"
      if op == "regex" && pattern = @pattern
        @compiled_regex = Regex.new(pattern, Regex::Options::IGNORE_CASE)
      end
    rescue ex
      # Log error - no need to log during compile_pattern
      @compiled_regex = nil
    end
  end

  # Rule loader and hot-reload manager
  class RuleLoader
    Log = ::Log.for("rule_loader")

    @rules : Array(Rule)
    @rule_dir : String
    @file_mtimes : Hash(String, Time)
    @mutex : Mutex

    def initialize(@rule_dir : String)
      @rules = [] of Rule
      @file_mtimes = {} of String => Time
      @mutex = Mutex.new
      load_rules
    end

    def rules : Array(Rule)
      @mutex.synchronize { @rules.dup }
    end

    def load_rules
      new_rules = [] of Rule
      new_mtimes = {} of String => Time

      # Recursive olarak tüm .yaml dosyalarını yükle
      Dir.glob(File.join(@rule_dir, "**", "*.yaml")).each do |file_path|
        begin
          mtime = File.info(file_path).modification_time
          new_mtimes[file_path] = mtime

          content = File.read(file_path)
          yaml_data = YAML.parse(content)

          # New format: root must be Hash and contain "rules" key
          unless yaml_data.raw.is_a?(Hash) && yaml_data["rules"]?
            Log.error { "Invalid YAML format #{file_path}: root must be a Hash and contain 'rules' key" }
            next
          end

          rules_node = yaml_data["rules"]
          unless rules_node.raw.is_a?(Array)
            Log.error { "Failed to load rules from #{file_path}: 'rules' key must be an Array" }
            next
          end

          rule_count = 0
          rules_node.as_a.each do |rule_node|
            # Convert each rule_node to YAML string and parse to Rule
            rule_yaml = rule_node.to_yaml
            rule = Rule.from_yaml(rule_yaml)
            rule.compile_pattern
            new_rules << rule
            rule_count += 1
          end
          Log.info { "Loaded #{rule_count} rules from #{file_path}" }
        rescue ex
          Log.error { "Failed to load rules from #{file_path}: #{ex.message}" }
          Log.error { ex.backtrace.join("\n") if ex.backtrace }
        end
      end

      @mutex.synchronize do
        @rules = new_rules
        @file_mtimes = new_mtimes
      end

      Log.info { "Total #{@rules.size} rules loaded" }
    end

    def check_and_reload
      needs_reload = false

      Dir.glob(File.join(@rule_dir, "**", "*.yaml")).each do |file_path|
        begin
          mtime = File.info(file_path).modification_time
          if !@file_mtimes.has_key?(file_path) || @file_mtimes[file_path] != mtime
            needs_reload = true
            break
          end
        rescue ex
          Log.warn { "File check failed for #{file_path}: #{ex.message}" }
        end
      end

      # Silinen dosyaları kontrol et
      @file_mtimes.keys.each do |file_path|
        if !File.exists?(file_path)
          needs_reload = true
          break
        end
      end

      if needs_reload
        Log.info { "Changes detected in rule files, reloading..." }
        load_rules
      end
    end

    def rule_count : Int32
      @mutex.synchronize { @rules.size }
    end
  end
end
