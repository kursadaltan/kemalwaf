require "yaml"
require "file"
require "atomic"

module KemalWAF
  # =============================================================================
  # IMMUTABLE RULE SNAPSHOT IMPLEMENTATION
  # =============================================================================
  # High-performance rule loading using:
  # - Immutable rule snapshots
  # - Atomic pointer swap for hot-reload
  # - Version tracking for snapshot identification
  # - Zero-downtime configuration updates
  # =============================================================================

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
            result << VariableSpec.new(item.value)
          when YAML::Nodes::Mapping
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

    # Scoring system - custom score overrides default_score
    property score : Int32?           # Custom score for this rule (optional)
    property default_score : Int32 = 1 # Default score if no custom score is set

    # Source file for rule management
    @[YAML::Field(ignore: true)]
    property source_file : String?

    @[YAML::Field(ignore: true)]
    property compiled_regex : Regex?

    def variable_specs : Array(VariableSpec)
      @variables
    end

    # Get effective score (custom score or default)
    def effective_score : Int32
      @score || @default_score
    end

    def initialize(@id, @msg, @variables : Array(VariableSpec), @pattern, @action, @transforms, @operator, @paranoia_level, @severity, @category, @tags, @name, @score = nil, @default_score = 1)
      @compiled_regex = nil
      @source_file = nil
      compile_pattern
    end

    def compile_pattern
      op = @operator || "regex"
      if op == "regex"
        if pattern = @pattern
          @compiled_regex = Regex.new(pattern, Regex::Options::IGNORE_CASE)
        end
      end
    rescue ex
      @compiled_regex = nil
    end
  end

  # =============================================================================
  # Immutable Rule Snapshot
  # =============================================================================
  # Represents a frozen, immutable collection of WAF rules
  # Once created, the rules cannot be modified
  # Used for atomic hot-reload without locks
  # =============================================================================
  class RuleSnapshot
    Log = ::Log.for("rule_snapshot")

    getter rules : Array(Rule)
    getter version : Int64
    getter created_at : Time
    getter rule_count : Int32
    getter file_checksums : Hash(String, String)

    def initialize(@rules : Array(Rule), @version : Int64, @file_checksums : Hash(String, String) = {} of String => String)
      @created_at = Time.utc
      @rule_count = @rules.size
      Log.info { "RuleSnapshot v#{@version} created with #{@rule_count} rules" }
    end

    # Empty snapshot for initialization
    def self.empty : RuleSnapshot
      new([] of Rule, 0_i64)
    end

    # Check if snapshot is empty
    def empty? : Bool
      @rules.empty?
    end

    # Get rule by ID (O(n) - consider index if needed)
    def find_by_id(id : Int32) : Rule?
      @rules.find { |r| r.id == id }
    end

    # Snapshot statistics
    def stats : NamedTuple(version: Int64, rule_count: Int32, created_at: Time)
      {version: @version, rule_count: @rule_count, created_at: @created_at}
    end
  end

  # =============================================================================
  # Atomic Snapshot Holder
  # =============================================================================
  # Thread-safe container for the current rule snapshot
  # Uses atomic operations for lock-free read access
  # =============================================================================
  class AtomicSnapshotHolder
    @current : RuleSnapshot
    @mutex : Mutex # Only used for writes

    def initialize
      @current = RuleSnapshot.empty
      @mutex = Mutex.new
    end

    # Get current snapshot (lock-free read)
    def get : RuleSnapshot
      @current
    end

    # Swap to new snapshot (atomic swap)
    def swap(new_snapshot : RuleSnapshot) : RuleSnapshot
      @mutex.synchronize do
        old = @current
        @current = new_snapshot
        old
      end
    end

    # Get current version
    def version : Int64
      @current.version
    end
  end

  # =============================================================================
  # Rule Loader with Immutable Snapshots
  # =============================================================================
  # Manages rule loading and hot-reload using immutable snapshots
  # All rule access is through snapshots for thread-safety
  # =============================================================================
  class RuleLoader
    Log = ::Log.for("rule_loader")

    @rule_dir : String
    @file_mtimes : Hash(String, Time)
    @snapshot_holder : AtomicSnapshotHolder
    @version_counter : Atomic(Int64)
    @mutex : Mutex # Only for file operations

    def initialize(@rule_dir : String)
      @file_mtimes = {} of String => Time
      @snapshot_holder = AtomicSnapshotHolder.new
      @version_counter = Atomic(Int64).new(0_i64)
      @mutex = Mutex.new
      load_rules
    end

    # Get current rules (lock-free through snapshot)
    # Get current rules (returns copy for thread-safety compatibility)
    def rules : Array(Rule)
      @snapshot_holder.get.rules.dup
    end

    # Get current snapshot
    def snapshot : RuleSnapshot
      @snapshot_holder.get
    end

    # Get current snapshot version
    def snapshot_version : Int64
      @snapshot_holder.version
    end

    # Load rules and create new snapshot
    def load_rules
      new_rules = [] of Rule
      new_mtimes = {} of String => Time
      new_checksums = {} of String => String

      # Load all YAML files recursively
      Dir.glob(File.join(@rule_dir, "**", "*.yaml")).each do |file_path|
        begin
          mtime = File.info(file_path).modification_time
          new_mtimes[file_path] = mtime

          content = File.read(file_path)
          new_checksums[file_path] = content.hash.to_s

          yaml_data = YAML.parse(content)

          unless yaml_data.raw.is_a?(Hash) && yaml_data["rules"]?
            Log.warn { "Invalid YAML format #{file_path}: root must be a Hash and contain 'rules' key" }
            next
          end

          rules_node = yaml_data["rules"]
          unless rules_node.raw.is_a?(Array)
            Log.warn { "Failed to load rules from #{file_path}: 'rules' key must be an Array" }
            next
          end

          rule_count = 0
          rules_node.as_a.each do |rule_node|
            rule_yaml = rule_node.to_yaml
            rule = Rule.from_yaml(rule_yaml)
            rule.source_file = file_path
            rule.compile_pattern
            new_rules << rule
            rule_count += 1
          end
          Log.info { "Loaded #{rule_count} rules from #{file_path}" }
        rescue ex
          Log.warn { "Failed to load rules from #{file_path}: #{ex.message}" }
          Log.debug { ex.backtrace.join("\n") if ex.backtrace }
        end
      end

      # Create new immutable snapshot
      new_version = @version_counter.add(1_i64)
      new_snapshot = RuleSnapshot.new(new_rules, new_version, new_checksums)

      # Atomic swap to new snapshot
      @mutex.synchronize do
        old_snapshot = @snapshot_holder.swap(new_snapshot)
        @file_mtimes = new_mtimes
        Log.info { "Snapshot swapped: v#{old_snapshot.version} -> v#{new_snapshot.version} (#{new_rules.size} rules)" }
      end

      Log.info { "Total #{new_rules.size} rules loaded in snapshot v#{new_version}" }
    end

    # Check for changes and reload if needed
    def check_and_reload : Bool
      needs_reload = false

      # Check for modified files
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

      # Check for deleted files
      unless needs_reload
        @file_mtimes.keys.each do |file_path|
          if !File.exists?(file_path)
            needs_reload = true
            break
          end
        end
      end

      if needs_reload
        Log.info { "Changes detected in rule files, reloading..." }
        load_rules
        true
      else
        false
      end
    end

    # Get rule count from current snapshot
    def rule_count : Int32
      @snapshot_holder.get.rule_count
    end

    # Get snapshot statistics
    def stats : NamedTuple(version: Int64, rule_count: Int32, created_at: Time)
      @snapshot_holder.get.stats
    end

    # Validate rules without activating (dry-run)
    def validate_rules(rule_dir : String? = nil) : NamedTuple(valid: Bool, errors: Array(String), rule_count: Int32)
      target_dir = rule_dir || @rule_dir
      errors = [] of String
      rule_count = 0

      Dir.glob(File.join(target_dir, "**", "*.yaml")).each do |file_path|
        begin
          content = File.read(file_path)
          yaml_data = YAML.parse(content)

          unless yaml_data.raw.is_a?(Hash) && yaml_data["rules"]?
            errors << "#{file_path}: Invalid YAML format"
            next
          end

          rules_node = yaml_data["rules"]
          unless rules_node.raw.is_a?(Array)
            errors << "#{file_path}: 'rules' key must be an Array"
            next
          end

          rules_node.as_a.each_with_index do |rule_node, idx|
            begin
              rule_yaml = rule_node.to_yaml
              rule = Rule.from_yaml(rule_yaml)
              rule.compile_pattern

              # Validate regex if present
              if rule.operator == "regex" && rule.pattern && rule.compiled_regex.nil?
                errors << "#{file_path}[#{idx}]: Invalid regex pattern '#{rule.pattern}'"
              end

              rule_count += 1
            rescue ex
              errors << "#{file_path}[#{idx}]: #{ex.message}"
            end
          end
        rescue ex
          errors << "#{file_path}: #{ex.message}"
        end
      end

      {valid: errors.empty?, errors: errors, rule_count: rule_count}
    end
  end
end
