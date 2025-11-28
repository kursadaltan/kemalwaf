require "log"

module KemalWAF
  # LibInjection C binding
  # Static library: lib/libinjection/libinjection.a
  # Library will be linked during build via build script or Makefile
  # Note: @[Link] directive removed to avoid duplicate linking
  lib LibInjection
    # Injection result enum
    enum InjectionResult : Int32
      FALSE = 0
      TRUE  = 1
      ERROR = 2
    end

    # SQLi detection - C function: libinjection_sqli
    # Returns: 1 if SQLi detected, 0 if benign, 2 if error
    fun libinjection_sqli(input : UInt8*, len : LibC::SizeT, fingerprint : UInt8*) : InjectionResult

    # XSS detection - C function: libinjection_xss
    # Returns: 1 if XSS detected, 0 if benign, 2 if error
    fun libinjection_xss(input : UInt8*, len : LibC::SizeT) : InjectionResult
  end

  # LibInjection wrapper with graceful fallback
  module LibInjectionWrapper
    Log = ::Log.for("libinjection")

    @@available : Bool?
    @@initialized = false

    # Check if LibInjection is available
    def self.available? : Bool
      if @@available
        return @@available.not_nil!
      end

      @@initialized = true

      begin
        # Test LibInjection with a simple benign input
        test_input = "test"
        fingerprint = uninitialized UInt8[8]
        result = LibInjection.libinjection_sqli(test_input.to_unsafe, test_input.bytesize, fingerprint.to_unsafe)

        # If we get here without exception, LibInjection is available
        @@available = true
        Log.info { "LibInjection successfully loaded" }
        true
      rescue ex
        @@available = false
        Log.warn { "LibInjection failed to load: #{ex.message}. libinjection_sqli and libinjection_xss operators will not work." }
        false
      end
    end

    # SQLi detection
    def self.detect_sqli(input : String) : Bool
      return false if input.empty?
      return false unless available?

      begin
        fingerprint = uninitialized UInt8[8]
        result = LibInjection.libinjection_sqli(input.to_unsafe, input.bytesize, fingerprint.to_unsafe)

        result == LibInjection::InjectionResult::TRUE
      rescue ex
        Log.error { "LibInjection SQLi detection error: #{ex.message}" }
        false
      end
    end

    # XSS detection
    def self.detect_xss(input : String) : Bool
      return false if input.empty?
      return false unless available?

      begin
        result = LibInjection.libinjection_xss(input.to_unsafe, input.bytesize)

        result == LibInjection::InjectionResult::TRUE
      rescue ex
        Log.error { "LibInjection XSS detection error: #{ex.message}" }
        false
      end
    end
  end
end
