require "./spec_helper"

describe KemalWAF::Metrics do
  describe "#initialize" do
    it "initializes with zero values" do
      metrics = KemalWAF::Metrics.new
      metrics.to_prometheus.should contain("waf_requests_total 0")
      metrics.to_prometheus.should contain("waf_blocked_total 0")
      metrics.to_prometheus.should contain("waf_observed_total 0")
      metrics.to_prometheus.should contain("waf_rate_limited_total 0")
      metrics.to_prometheus.should contain("waf_rules_loaded 0")
    end
  end

  describe "#increment_requests" do
    it "increments request counter" do
      metrics = KemalWAF::Metrics.new
      metrics.increment_requests
      metrics.increment_requests
      metrics.to_prometheus.should contain("waf_requests_total 2")
    end

    it "is thread-safe" do
      metrics = KemalWAF::Metrics.new

      # Thread-safe test için paralel increment
      channel = Channel(Nil).new
      10.times do
        spawn do
          100.times do
            metrics.increment_requests
          end
          channel.send(nil)
        end
      end

      # Tüm thread'lerin bitmesini bekle
      10.times { channel.receive }

      metrics.to_prometheus.should contain("waf_requests_total 1000")
    end
  end

  describe "#increment_blocked" do
    it "increments blocked counter" do
      metrics = KemalWAF::Metrics.new
      metrics.increment_blocked
      metrics.increment_blocked
      metrics.to_prometheus.should contain("waf_blocked_total 2")
    end

    it "is thread-safe" do
      metrics = KemalWAF::Metrics.new

      channel = Channel(Nil).new
      5.times do
        spawn do
          50.times do
            metrics.increment_blocked
          end
          channel.send(nil)
        end
      end

      5.times { channel.receive }

      metrics.to_prometheus.should contain("waf_blocked_total 250")
    end
  end

  describe "#increment_observed" do
    it "increments observed counter" do
      metrics = KemalWAF::Metrics.new
      metrics.increment_observed
      metrics.to_prometheus.should contain("waf_observed_total 1")
    end
  end

  describe "#increment_rate_limited" do
    it "increments rate limited counter" do
      metrics = KemalWAF::Metrics.new
      metrics.increment_rate_limited
      metrics.increment_rate_limited
      metrics.to_prometheus.should contain("waf_rate_limited_total 2")
    end
  end

  describe "#set_rules_loaded" do
    it "sets rules loaded gauge" do
      metrics = KemalWAF::Metrics.new
      metrics.set_rules_loaded(42)
      metrics.to_prometheus.should contain("waf_rules_loaded 42")
    end

    it "updates rules loaded gauge" do
      metrics = KemalWAF::Metrics.new
      metrics.set_rules_loaded(10)
      metrics.set_rules_loaded(20)
      metrics.to_prometheus.should contain("waf_rules_loaded 20")
    end
  end

  describe "#to_prometheus" do
    it "returns valid Prometheus format" do
      metrics = KemalWAF::Metrics.new
      metrics.increment_requests
      metrics.increment_blocked
      metrics.increment_observed
      metrics.increment_rate_limited
      metrics.set_rules_loaded(5)

      output = metrics.to_prometheus

      # Prometheus format kontrolü
      output.should contain("# HELP")
      output.should contain("# TYPE")
      output.should contain("counter")
      output.should contain("gauge")
      output.should contain("waf_requests_total 1")
      output.should contain("waf_blocked_total 1")
      output.should contain("waf_observed_total 1")
      output.should contain("waf_rate_limited_total 1")
      output.should contain("waf_rules_loaded 5")
    end

    it "includes all required metrics" do
      metrics = KemalWAF::Metrics.new
      output = metrics.to_prometheus

      output.should contain("waf_requests_total")
      output.should contain("waf_blocked_total")
      output.should contain("waf_observed_total")
      output.should contain("waf_rate_limited_total")
      output.should contain("waf_rules_loaded")
    end

    it "includes help text for each metric" do
      metrics = KemalWAF::Metrics.new
      output = metrics.to_prometheus

      output.should contain("# HELP waf_requests_total")
      output.should contain("# HELP waf_blocked_total")
      output.should contain("# HELP waf_observed_total")
      output.should contain("# HELP waf_rate_limited_total")
      output.should contain("# HELP waf_rules_loaded")
    end

    it "includes type information for each metric" do
      metrics = KemalWAF::Metrics.new
      output = metrics.to_prometheus

      output.should contain("# TYPE waf_requests_total counter")
      output.should contain("# TYPE waf_blocked_total counter")
      output.should contain("# TYPE waf_observed_total counter")
      output.should contain("# TYPE waf_rate_limited_total counter")
      output.should contain("# TYPE waf_rules_loaded gauge")
    end
  end
end
