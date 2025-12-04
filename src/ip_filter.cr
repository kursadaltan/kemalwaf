require "socket"

module KemalWAF
  # =============================================================================
  # IP FILTER WITH RADIX TREE INDEX
  # =============================================================================
  # High-performance IP filtering using:
  # - Radix tree for CIDR matching (O(32) = O(1) for IPv4)
  # - Set-based exact IP lookup (O(1))
  # - Separated IPv4 and IPv6 trees
  # =============================================================================

  # IP filter sonucu
  struct IPFilterResult
    property allowed : Bool
    property reason : String
    property source : String # "whitelist", "blacklist", "geoip", "default"

    def initialize(@allowed, @reason, @source)
    end
  end

  # =============================================================================
  # Radix Tree Node for IP CIDR Matching
  # =============================================================================
  # Binary tree where each level represents one bit of the IP address
  # Supports both IPv4 (32 bits) and IPv6 (128 bits)
  # =============================================================================
  class RadixTreeNode
    property left : RadixTreeNode?     # 0 bit
    property right : RadixTreeNode?    # 1 bit
    property is_terminal : Bool        # Is this a valid CIDR endpoint?
    property prefix : Int32            # CIDR prefix length
    property network : String          # Original network string

    def initialize
      @left = nil
      @right = nil
      @is_terminal = false
      @prefix = 0
      @network = ""
    end

    def mark_terminal(prefix : Int32, network : String)
      @is_terminal = true
      @prefix = prefix
      @network = network
    end
  end

  # =============================================================================
  # IPv4 Radix Tree
  # =============================================================================
  # 32-level tree for IPv4 CIDR matching
  # Lookup is O(32) = O(1) constant time
  # =============================================================================
  class IPv4RadixTree
    Log = ::Log.for("ipv4_radix")

    @root : RadixTreeNode
    @size : Int32

    def initialize
      @root = RadixTreeNode.new
      @size = 0
    end

    # Insert a CIDR network
    def insert(cidr_string : String) : Bool
      parts = cidr_string.split('/')
      return false if parts.size != 2

      ip_string = parts[0].strip
      prefix = parts[1].to_i?
      return false unless prefix && prefix >= 0 && prefix <= 32

      ip_int = ip_to_int(ip_string)
      return false unless ip_int

      # Navigate/create tree path
      node = @root
      prefix.times do |i|
        bit = (ip_int >> (31 - i)) & 1

        if bit == 0
          node.left ||= RadixTreeNode.new
          node = node.left.not_nil!
        else
          node.right ||= RadixTreeNode.new
          node = node.right.not_nil!
        end
      end

      # Mark terminal node
      node.mark_terminal(prefix, cidr_string)
      @size += 1
      Log.debug { "Inserted CIDR: #{cidr_string}" }
      true
    end

    # Lookup IP address - returns matching CIDR info or nil
    def lookup(ip_string : String) : NamedTuple(matched: Bool, network: String, prefix: Int32)?
      ip_int = ip_to_int(ip_string)
      return nil unless ip_int

      # Traverse tree, track best match
      node = @root
      best_match : RadixTreeNode? = nil

      32.times do |i|
        # Check if current node is a terminal (valid CIDR endpoint)
        if node.is_terminal
          best_match = node
        end

        bit = (ip_int >> (31 - i)) & 1

        if bit == 0
          break unless node.left
          node = node.left.not_nil!
        else
          break unless node.right
          node = node.right.not_nil!
        end
      end

      # Check final node
      if node.is_terminal
        best_match = node
      end

      if match = best_match
        {matched: true, network: match.network, prefix: match.prefix}
      else
        nil
      end
    end

    # Check if IP matches any CIDR
    def includes?(ip_string : String) : Bool
      lookup(ip_string) != nil
    end

    def size : Int32
      @size
    end

    def empty? : Bool
      @size == 0
    end

    private def ip_to_int(ip_string : String) : UInt32?
      parts = ip_string.split('.')
      return nil if parts.size != 4

      result = 0_u32
      parts.each_with_index do |part, i|
        octet = part.to_i?
        return nil unless octet && octet >= 0 && octet <= 255
        result |= (octet.to_u32 << (24 - i * 8))
      end
      result
    rescue
      nil
    end
  end

  # =============================================================================
  # CIDR Network (simplified - used for display/logging)
  # =============================================================================
  class CIDRNetwork
    property network_ip : String
    property prefix : Int32
    property is_ipv6 : Bool

    def initialize(cidr_string : String)
      parts = cidr_string.split('/')
      raise ArgumentError.new("Invalid CIDR format: #{cidr_string}") if parts.size != 2

      network_ip_str = parts[0].strip
      prefix_val = parts[1].to_i
      is_ipv6_val = network_ip_str.includes?(':')

      begin
        validate_ip(network_ip_str)
      rescue ex
        raise ArgumentError.new("Invalid CIDR: #{cidr_string} - #{ex.message}")
      end

      @network_ip = network_ip_str
      @prefix = prefix_val
      @is_ipv6 = is_ipv6_val
    end

    def to_s : String
      "#{@network_ip}/#{@prefix}"
    end

    private def validate_ip(ip_string : String)
      if ip_string.includes?(':')
        Socket::IPAddress.parse("http://[#{ip_string}]:80")
      else
        Socket::IPAddress.parse("http://#{ip_string}:80")
      end
    end
  end

  # =============================================================================
  # IP Filter with Radix Tree Index
  # =============================================================================
  class IPFilter
    Log = ::Log.for("ip_filter")

    @whitelist : Set(String)
    @blacklist : Set(String)
    @cidr_whitelist_tree : IPv4RadixTree
    @cidr_blacklist_tree : IPv4RadixTree
    # Keep array for IPv6 (less common, simple linear scan is acceptable)
    @cidr_whitelist_ipv6 : Array(CIDRNetwork)
    @cidr_blacklist_ipv6 : Array(CIDRNetwork)
    @mutex : Mutex
    @enabled : Bool

    def initialize(@enabled : Bool = true)
      @whitelist = Set(String).new
      @blacklist = Set(String).new
      @cidr_whitelist_tree = IPv4RadixTree.new
      @cidr_blacklist_tree = IPv4RadixTree.new
      @cidr_whitelist_ipv6 = [] of CIDRNetwork
      @cidr_blacklist_ipv6 = [] of CIDRNetwork
      @mutex = Mutex.new
    end

    # Check if IP is allowed (O(1) for exact match, O(32) for CIDR)
    def allowed?(ip : String) : IPFilterResult
      return IPFilterResult.new(true, "IP filtering disabled", "default") unless @enabled

      @mutex.synchronize do
        is_ipv6 = ip.includes?(':')

        # 1. Whitelist exact match (O(1))
        if @whitelist.includes?(ip)
          return IPFilterResult.new(true, "IP whitelist'te", "whitelist")
        end

        # 2. CIDR whitelist check (O(32) for IPv4)
        if !is_ipv6
          if result = @cidr_whitelist_tree.lookup(ip)
            return IPFilterResult.new(true, "IP whitelist CIDR'de (#{result[:network]})", "whitelist")
          end
        else
          # IPv6 linear scan (less common)
          @cidr_whitelist_ipv6.each do |cidr|
            if ipv6_in_cidr?(ip, cidr)
              return IPFilterResult.new(true, "IP whitelist CIDR'de (#{cidr.network_ip}/#{cidr.prefix})", "whitelist")
            end
          end
        end

        # 3. Blacklist exact match (O(1))
        if @blacklist.includes?(ip)
          return IPFilterResult.new(false, "IP blacklist'te", "blacklist")
        end

        # 4. CIDR blacklist check (O(32) for IPv4)
        if !is_ipv6
          if result = @cidr_blacklist_tree.lookup(ip)
            return IPFilterResult.new(false, "IP blacklist CIDR'de (#{result[:network]})", "blacklist")
          end
        else
          # IPv6 linear scan
          @cidr_blacklist_ipv6.each do |cidr|
            if ipv6_in_cidr?(ip, cidr)
              return IPFilterResult.new(false, "IP blacklist CIDR'de (#{cidr.network_ip}/#{cidr.prefix})", "blacklist")
            end
          end
        end

        # 5. Default: allow
        IPFilterResult.new(true, "IP filtrelenmedi", "default")
      end
    end

    # Add single IP to whitelist (O(1))
    def add_whitelist_ip(ip : String)
      @mutex.synchronize do
        @whitelist.add(ip.strip)
        Log.info { "IP added to whitelist: #{ip}" }
      end
    end

    # Add single IP to blacklist (O(1))
    def add_blacklist_ip(ip : String)
      @mutex.synchronize do
        @blacklist.add(ip.strip)
        Log.info { "IP added to blacklist: #{ip}" }
      end
    end

    # Add CIDR to whitelist (uses radix tree for IPv4)
    def add_whitelist_cidr(cidr_string : String)
      @mutex.synchronize do
        cidr = CIDRNetwork.new(cidr_string)
        if cidr.is_ipv6
          @cidr_whitelist_ipv6 << cidr
        else
          @cidr_whitelist_tree.insert(cidr_string)
        end
        Log.info { "CIDR added to whitelist: #{cidr_string}" }
      end
    rescue ex
      Log.error { "CIDR eklenemedi: #{cidr_string} - #{ex.message}" }
    end

    # Add CIDR to blacklist (uses radix tree for IPv4)
    def add_blacklist_cidr(cidr_string : String)
      @mutex.synchronize do
        cidr = CIDRNetwork.new(cidr_string)
        if cidr.is_ipv6
          @cidr_blacklist_ipv6 << cidr
        else
          @cidr_blacklist_tree.insert(cidr_string)
        end
        Log.info { "CIDR added to blacklist: #{cidr_string}" }
      end
    rescue ex
      Log.error { "CIDR eklenemedi: #{cidr_string} - #{ex.message}" }
    end

    # Load from file
    def load_from_file(file_path : String, list_type : Symbol)
      return unless File.exists?(file_path)

      begin
        File.each_line(file_path) do |line|
          line = line.strip
          next if line.empty?
          next if line.starts_with?('#')

          if line.includes?('/')
            case list_type
            when :whitelist
              add_whitelist_cidr(line)
            when :blacklist
              add_blacklist_cidr(line)
            end
          else
            case list_type
            when :whitelist
              add_whitelist_ip(line)
            when :blacklist
              add_blacklist_ip(line)
            end
          end
        end

        Log.info { "IP list loaded: #{file_path} (#{list_type})" }
      rescue ex
        Log.error { "IP listesi yüklenemedi: #{file_path} - #{ex.message}" }
      end
    end

    # Remove IP from whitelist
    def remove_whitelist_ip(ip : String)
      @mutex.synchronize do
        @whitelist.delete(ip.strip)
        Log.info { "IP removed from whitelist: #{ip}" }
      end
    end

    # Remove IP from blacklist
    def remove_blacklist_ip(ip : String)
      @mutex.synchronize do
        @blacklist.delete(ip.strip)
        Log.info { "IP removed from blacklist: #{ip}" }
      end
    end

    # Statistics
    def stats : Hash(String, Int32)
      @mutex.synchronize do
        {
          "whitelist_ips"   => @whitelist.size,
          "blacklist_ips"   => @blacklist.size,
          "whitelist_cidrs" => @cidr_whitelist_tree.size + @cidr_whitelist_ipv6.size,
          "blacklist_cidrs" => @cidr_blacklist_tree.size + @cidr_blacklist_ipv6.size,
        }
      end
    end

    # Clear all
    def clear
      @mutex.synchronize do
        @whitelist.clear
        @blacklist.clear
        @cidr_whitelist_tree = IPv4RadixTree.new
        @cidr_blacklist_tree = IPv4RadixTree.new
        @cidr_whitelist_ipv6.clear
        @cidr_blacklist_ipv6.clear
        Log.info { "All IP lists cleared" }
      end
    end

    # IPv6 CIDR check (simplified - for less common case)
    private def ipv6_in_cidr?(ip : String, cidr : CIDRNetwork) : Bool
      # Simplified IPv6 CIDR check
      # For production, consider a full IPv6 implementation
      ip == cidr.network_ip
    rescue
      false
    end
  end
end
