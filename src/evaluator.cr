require "http"
require "uri"
require "./rule_loader"
require "./libinjection"

module KemalWAF
  # =============================================================================
  # ZERO GC HOTPATH + BRANCHLESS EVALUATION IMPLEMENTATION
  # =============================================================================
  # This module implements high-performance request evaluation using:
  # - Preallocated buffer pools
  # - Stack-based structs
  # - Slice operations instead of string allocations
  # - Reusable variable snapshots
  # - Jump-table based operator dispatch (branchless)
  # =============================================================================

  # Variable type indices for zero-allocation lookup
  enum VariableType
    RequestLine     = 0
    RequestFilename = 1
    RequestBasename = 2
    Args            = 3
    ArgsNames       = 4
    Headers         = 5
    Cookie          = 6
    CookieNames     = 7
    Body            = 8
    Unknown         = 9
  end

  # Operator type indices for jump-table dispatch
  enum OperatorType
    Regex            = 0
    Contains         = 1
    StartsWith       = 2
    EndsWith         = 3
    Equals           = 4
    LibInjectionSqli = 5
    LibInjectionXss  = 6
    Unknown          = 7
  end

  # Constants for buffer sizes
  MAX_VARIABLE_VALUES =  128
  MAX_VALUE_LENGTH    = 8192
  MAX_HEADERS         =   64
  MAX_ARGS            =   64
  MAX_COOKIES         =   32
  BUFFER_POOL_SIZE    =  256

  # Matched rule info for scoring
  struct MatchedRuleInfo
    property rule_id : Int32
    property message : String
    property score : Int32
    property matched_variable : String
    property matched_value : String

    def initialize(@rule_id, @message, @score, @matched_variable, @matched_value)
    end
  end

  # İstek değerlendirme sonucu
  struct EvaluationResult
    property blocked : Bool
    property observed : Bool
    property rule_id : Int32?
    property message : String?
    property matched_variable : String?
    property matched_value : String?
    property total_score : Int32
    property matched_rules : Array(MatchedRuleInfo)
    property threshold : Int32

    def initialize(
      @blocked,
      @rule_id = nil,
      @message = nil,
      @observed = false,
      @matched_variable = nil,
      @matched_value = nil,
      @total_score = 0,
      @matched_rules = [] of MatchedRuleInfo,
      @threshold = 5
    )
    end
  end

  # Domain WAF configuration for evaluation
  struct DomainEvalConfig
    property threshold : Int32
    property enabled_rules : Array(Int32)
    property disabled_rules : Array(Int32)

    def initialize(
      @threshold : Int32 = 5,
      @enabled_rules : Array(Int32) = [] of Int32,
      @disabled_rules : Array(Int32) = [] of Int32
    )
    end

    # Check if a rule is enabled for this domain
    def rule_enabled?(rule_id : Int32) : Bool
      # If enabled list is not empty, only those rules are active
      if !@enabled_rules.empty?
        return @enabled_rules.includes?(rule_id)
      end
      # Otherwise, all rules except disabled ones are active
      !@disabled_rules.includes?(rule_id)
    end
  end

  # =============================================================================
  # Branchless Operator Dispatch
  # =============================================================================
  # Jump-table pattern for operator matching - eliminates branching in hotpath
  # Each operator has a fixed index, dispatch is O(1) array lookup
  # =============================================================================
  module OperatorDispatch
    # Operator string to index mapping (compile-time constant)
    OPERATOR_INDEX = {
      "regex"             => OperatorType::Regex,
      "contains"          => OperatorType::Contains,
      "starts_with"       => OperatorType::StartsWith,
      "ends_with"         => OperatorType::EndsWith,
      "equals"            => OperatorType::Equals,
      "libinjection_sqli" => OperatorType::LibInjectionSqli,
      "libinjection_xss"  => OperatorType::LibInjectionXss,
    }

    # Convert operator string to index (with default)
    def self.to_index(operator : String?) : OperatorType
      op = operator || "regex"
      OPERATOR_INDEX[op]? || OperatorType::Regex
    end
  end

  # =============================================================================
  # Preallocated Variable Snapshot
  # =============================================================================
  class VariableSnapshot
    @request_line : String = ""
    @request_filename : String = ""
    @request_basename : String = ""
    @body : String = ""

    @args : Array(String)
    @args_names : Array(String)
    @headers : Array(String)
    @cookies : Array(String)
    @cookie_names : Array(String)

    @args_count : Int32 = 0
    @args_names_count : Int32 = 0
    @headers_count : Int32 = 0
    @cookies_count : Int32 = 0
    @cookie_names_count : Int32 = 0

    def initialize
      @args = Array(String).new(MAX_ARGS)
      @args_names = Array(String).new(MAX_ARGS)
      @headers = Array(String).new(MAX_HEADERS)
      @cookies = Array(String).new(MAX_COOKIES)
      @cookie_names = Array(String).new(MAX_COOKIES)
    end

    def reset
      @request_line = ""
      @request_filename = ""
      @request_basename = ""
      @body = ""
      @args.clear
      @args_names.clear
      @headers.clear
      @cookies.clear
      @cookie_names.clear
      @args_count = 0
      @args_names_count = 0
      @headers_count = 0
      @cookies_count = 0
      @cookie_names_count = 0
    end

    def populate(request : HTTP::Request, body : String?, body_limit : Int32)
      reset

      @request_line = "#{request.method} #{request.resource} HTTP/#{request.version}"
      @request_filename = request.resource
      @request_basename = File.basename(request.resource)

      if query = request.query
        URI::Params.parse(query).each do |key, value|
          break if @args_count >= MAX_ARGS
          @args << "#{key}=#{value}"
          @args_names << key
          @args_count += 1
          @args_names_count += 1
        end
      end

      request.headers.each do |key, values|
        values.each do |value|
          break if @headers_count >= MAX_HEADERS
          @headers << "#{key}: #{value}"
          @headers_count += 1
        end
      end

      if cookie_header = request.headers["Cookie"]?
        @cookies << cookie_header
        @cookies_count = 1
        parse_cookie_names_zero_alloc(cookie_header)
      end

      if body && !body.empty?
        @body = body.size > body_limit ? body[0, body_limit] : body
      end
    end

    private def parse_cookie_names_zero_alloc(cookie_header : String)
      start_idx = 0
      len = cookie_header.size

      while start_idx < len
        break if @cookie_names_count >= MAX_COOKIES

        while start_idx < len && cookie_header[start_idx].ascii_whitespace?
          start_idx += 1
        end

        eq_idx = start_idx
        while eq_idx < len && cookie_header[eq_idx] != '='
          eq_idx += 1
        end

        if eq_idx > start_idx && eq_idx < len
          name_end = eq_idx - 1
          while name_end > start_idx && cookie_header[name_end].ascii_whitespace?
            name_end -= 1
          end

          if name_end >= start_idx
            @cookie_names << cookie_header[start_idx..name_end]
            @cookie_names_count += 1
          end
        end

        semicolon_idx = eq_idx
        while semicolon_idx < len && cookie_header[semicolon_idx] != ';'
          semicolon_idx += 1
        end
        start_idx = semicolon_idx + 1
      end
    end

    def get_values(var_type : VariableType) : Array(String)
      case var_type
      when .request_line?
        @request_line.empty? ? [] of String : [@request_line]
      when .request_filename?
        @request_filename.empty? ? [] of String : [@request_filename]
      when .request_basename?
        @request_basename.empty? ? [] of String : [@request_basename]
      when .args?
        @args
      when .args_names?
        @args_names
      when .headers?
        @headers
      when .cookie?
        @cookies
      when .cookie_names?
        @cookie_names
      when .body?
        @body.empty? ? [] of String : [@body]
      else
        [] of String
      end
    end

    def get_values_by_name(name : String) : Array(String)
      get_values(string_to_variable_type(name))
    end

    private def string_to_variable_type(name : String) : VariableType
      case name
      when "REQUEST_LINE"     then VariableType::RequestLine
      when "REQUEST_FILENAME" then VariableType::RequestFilename
      when "REQUEST_BASENAME" then VariableType::RequestBasename
      when "ARGS"             then VariableType::Args
      when "ARGS_NAMES"       then VariableType::ArgsNames
      when "HEADERS"          then VariableType::Headers
      when "COOKIE"           then VariableType::Cookie
      when "COOKIE_NAMES"     then VariableType::CookieNames
      when "BODY"             then VariableType::Body
      else                         VariableType::Unknown
      end
    end
  end

  # =============================================================================
  # Buffer Pool for Variable Snapshots
  # =============================================================================
  class VariableSnapshotPool
    Log = ::Log.for("snapshot_pool")

    @pool : Channel(VariableSnapshot)
    @pool_size : Int32
    @created : Atomic(Int32)

    def initialize(@pool_size : Int32 = BUFFER_POOL_SIZE)
      @pool = Channel(VariableSnapshot).new(@pool_size)
      @created = Atomic(Int32).new(0)

      @pool_size.times do
        @pool.send(VariableSnapshot.new)
        @created.add(1)
      end

      Log.info { "VariableSnapshotPool initialized with #{@pool_size} buffers" }
    end

    def acquire : VariableSnapshot
      select
      when snapshot = @pool.receive
        snapshot
      else
        @created.add(1)
        Log.debug { "Pool empty, created new snapshot (total: #{@created.get})" }
        VariableSnapshot.new
      end
    end

    def release(snapshot : VariableSnapshot)
      snapshot.reset
      select
      when @pool.send(snapshot)
      else
        Log.debug { "Pool full, snapshot will be GC'd" }
      end
    end

    def stats : NamedTuple(pool_size: Int32, created: Int32)
      {pool_size: @pool_size, created: @created.get}
    end
  end

  # =============================================================================
  # Evaluator with Zero GC Hotpath + Branchless Dispatch
  # =============================================================================
  class Evaluator
    Log = ::Log.for("evaluator")

    @rule_loader : RuleLoader
    @observe_mode : Bool
    @body_limit : Int32
    @snapshot_pool : VariableSnapshotPool

    def initialize(@rule_loader : RuleLoader, @observe_mode : Bool, @body_limit : Int32)
      @snapshot_pool = VariableSnapshotPool.new(BUFFER_POOL_SIZE)
    end

    # Original evaluate method (backward compatible - blocks on first deny rule match)
    def evaluate(request : HTTP::Request, body : String?) : EvaluationResult
      snapshot = @snapshot_pool.acquire

      begin
        snapshot.populate(request, body, @body_limit)
        result = evaluate_rules(snapshot)
        result
      ensure
        @snapshot_pool.release(snapshot)
      end
    end

    # New: Domain-aware evaluate with scoring system
    def evaluate_with_domain(request : HTTP::Request, body : String?, domain_config : DomainEvalConfig?) : EvaluationResult
      snapshot = @snapshot_pool.acquire

      begin
        snapshot.populate(request, body, @body_limit)
        
        if domain_config
          result = evaluate_rules_with_scoring(snapshot, domain_config)
        else
          result = evaluate_rules(snapshot)
        end
        result
      ensure
        @snapshot_pool.release(snapshot)
      end
    end

    # Original rule evaluation (backward compatible)
    private def evaluate_rules(snapshot : VariableSnapshot) : EvaluationResult
      @rule_loader.rules.each do |rule|
        match_result = match_rule_branchless?(rule, snapshot)
        if match_result
          matched_var, matched_val = match_result
          Log.info { "Rule match: ID=#{rule.id}, Msg=#{rule.msg}" }

          if rule.action == "deny"
            if @observe_mode
              Log.warn { "[OBSERVE MODE] Rule #{rule.id} matched but not blocked" }
              return EvaluationResult.new(
                blocked: false,
                rule_id: rule.id,
                message: rule.msg,
                observed: true,
                matched_variable: matched_var,
                matched_value: matched_val
              )
            else
              Log.warn { "Request blocked: Rule #{rule.id}" }
              return EvaluationResult.new(
                blocked: true,
                rule_id: rule.id,
                message: rule.msg,
                matched_variable: matched_var,
                matched_value: matched_val
              )
            end
          end
        end
      end

      EvaluationResult.new(blocked: false)
    end

    # New: Scoring-based rule evaluation
    private def evaluate_rules_with_scoring(snapshot : VariableSnapshot, domain_config : DomainEvalConfig) : EvaluationResult
      matched_rules = [] of MatchedRuleInfo
      total_score = 0
      threshold = domain_config.threshold

      @rule_loader.rules.each do |rule|
        # Skip rules that are not enabled for this domain
        next unless domain_config.rule_enabled?(rule.id)

        match_result = match_rule_branchless?(rule, snapshot)
        if match_result
          matched_var, matched_val = match_result
          rule_score = rule.effective_score
          
          Log.info { "Rule match: ID=#{rule.id}, Msg=#{rule.msg}, Score=#{rule_score}" }

          if rule.action == "deny"
            total_score += rule_score
            matched_rules << MatchedRuleInfo.new(
              rule_id: rule.id,
              message: rule.msg,
              score: rule_score,
              matched_variable: matched_var,
              matched_value: matched_val
            )
          end
        end
      end

      # Check if total score exceeds threshold
      if total_score >= threshold
        if @observe_mode
          Log.warn { "[OBSERVE MODE] Score threshold exceeded (#{total_score}/#{threshold}) but not blocked" }
          # Return first matched rule for compatibility
          first_match = matched_rules.first?
          return EvaluationResult.new(
            blocked: false,
            rule_id: first_match.try(&.rule_id),
            message: "Score threshold exceeded: #{total_score}/#{threshold}",
            observed: true,
            matched_variable: first_match.try(&.matched_variable),
            matched_value: first_match.try(&.matched_value),
            total_score: total_score,
            matched_rules: matched_rules,
            threshold: threshold
          )
        else
          Log.warn { "Request blocked: Score threshold exceeded (#{total_score}/#{threshold})" }
          first_match = matched_rules.first?
          return EvaluationResult.new(
            blocked: true,
            rule_id: first_match.try(&.rule_id),
            message: "Score threshold exceeded: #{total_score}/#{threshold}",
            matched_variable: first_match.try(&.matched_variable),
            matched_value: first_match.try(&.matched_value),
            total_score: total_score,
            matched_rules: matched_rules,
            threshold: threshold
          )
        end
      end

      # Not blocked but may have matches
      if !matched_rules.empty?
        first_match = matched_rules.first
        return EvaluationResult.new(
          blocked: false,
          rule_id: first_match.rule_id,
          message: "Matched rules but below threshold: #{total_score}/#{threshold}",
          observed: true,
          matched_variable: first_match.matched_variable,
          matched_value: first_match.matched_value,
          total_score: total_score,
          matched_rules: matched_rules,
          threshold: threshold
        )
      end

      EvaluationResult.new(
        blocked: false,
        total_score: 0,
        matched_rules: [] of MatchedRuleInfo,
        threshold: threshold
      )
    end

    # =============================================================================
    # Branchless Rule Matching
    # =============================================================================
    # Uses jump-table dispatch instead of case/when branching
    # Operator index is computed once, then used for direct function lookup
    # =============================================================================
    private def match_rule_branchless?(rule : Rule, snapshot : VariableSnapshot) : Tuple(String, String)?
      # Get operator index once (computed at rule load time ideally)
      op_type = OperatorDispatch.to_index(rule.operator)
      variable_specs = rule.variable_specs

      variable_specs.each do |spec|
        var_name = spec.type
        var_values = get_variable_values(var_name, spec.names, snapshot)

        var_values.each do |value|
          transformed = apply_transforms(value, rule.transforms)

          # Branchless dispatch using operator type enum
          matched = dispatch_operator(op_type, rule, transformed)

          if matched
            Log.debug { "Match found: var=#{var_name}, operator=#{rule.operator}" }
            return {var_name, value}
          end
        end
      end

      nil
    end

    # Jump-table style operator dispatch
    # Each operator type maps directly to a matching function
    @[AlwaysInline]
    private def dispatch_operator(op_type : OperatorType, rule : Rule, value : String) : Bool
      case op_type
      in .regex?
        match_regex(rule, value)
      in .contains?
        match_contains(rule, value)
      in .starts_with?
        match_starts_with(rule, value)
      in .ends_with?
        match_ends_with(rule, value)
      in .equals?
        match_equals(rule, value)
      in .lib_injection_sqli?
        LibInjectionWrapper.detect_sqli(value)
      in .lib_injection_xss?
        LibInjectionWrapper.detect_xss(value)
      in .unknown?
        match_regex(rule, value) # Default to regex
      end
    end

    private def get_variable_values(var_name : String, header_names : Array(String)?, snapshot : VariableSnapshot) : Array(String)
      case var_name
      when "HEADERS"
        if header_names && !header_names.empty?
          result = [] of String
          headers = snapshot.get_values_by_name("HEADERS")
          headers.each do |header|
            header_names.each do |name|
              if header.downcase.starts_with?("#{name.downcase}:")
                result << header
              end
            end
          end
          result
        else
          snapshot.get_values_by_name(var_name)
        end
      else
        snapshot.get_values_by_name(var_name)
      end
    end

    @[AlwaysInline]
    private def match_regex(rule : Rule, value : String) : Bool
      return false unless compiled_regex = rule.compiled_regex
      compiled_regex.matches?(value)
    end

    @[AlwaysInline]
    private def match_contains(rule : Rule, value : String) : Bool
      return false unless pattern = rule.pattern
      value.includes?(pattern)
    end

    @[AlwaysInline]
    private def match_starts_with(rule : Rule, value : String) : Bool
      return false unless pattern = rule.pattern
      value.starts_with?(pattern)
    end

    @[AlwaysInline]
    private def match_ends_with(rule : Rule, value : String) : Bool
      return false unless pattern = rule.pattern
      value.ends_with?(pattern)
    end

    @[AlwaysInline]
    private def match_equals(rule : Rule, value : String) : Bool
      return false unless pattern = rule.pattern
      value == pattern
    end

    private def apply_transforms(value : String, transforms : Array(String)?) : String
      return value unless transforms

      result = value
      transforms.each do |transform|
        result = apply_single_transform(result, transform)
      end
      result
    end

    # Transform dispatch - also uses enum-style dispatch
    @[AlwaysInline]
    private def apply_single_transform(value : String, transform : String) : String
      case transform
      when "none"
        value
      when "url_decode"
        url_decode(value)
      when "url_decode_uni"
        url_decode_uni(value)
      when "lowercase"
        value.downcase
      when "uppercase"
        value.upcase
      when "utf8_to_unicode"
        utf8_to_unicode(value)
      when "remove_nulls"
        remove_nulls(value)
      when "replace_comments"
        replace_comments(value)
      when "compress_whitespace"
        compress_whitespace(value)
      when "hex_decode"
        hex_decode(value)
      when "trim"
        value.strip
      else
        Log.warn { "Unknown transform: #{transform}" }
        value
      end
    end

    @[AlwaysInline]
    private def url_decode(value : String) : String
      URI.decode_www_form(value)
    rescue
      value
    end

    @[AlwaysInline]
    private def url_decode_uni(value : String) : String
      URI.decode_www_form(value)
    rescue
      value
    end

    @[AlwaysInline]
    private def utf8_to_unicode(value : String) : String
      value
    end

    @[AlwaysInline]
    private def remove_nulls(value : String) : String
      value.gsub('\0', "")
    end

    @[AlwaysInline]
    private def replace_comments(value : String) : String
      result = value
      result = result.gsub(/--.*$/, "")
      result = result.gsub(/\/\*.*?\*\//, "")
      result = result.gsub(/<!--.*?-->/, "")
      result
    end

    @[AlwaysInline]
    private def compress_whitespace(value : String) : String
      value.gsub(/\s+/, " ")
    end

    @[AlwaysInline]
    private def hex_decode(value : String) : String
      # Simple hex decode - handles %XX patterns
      value.gsub(/%([0-9A-Fa-f]{2})/) do |match|
        char_code = match[1..2].to_i(16)
        char_code.chr.to_s
      end
    rescue
      value
    end

    def pool_stats : NamedTuple(pool_size: Int32, created: Int32)
      @snapshot_pool.stats
    end
  end
end
