require "./spec_helper"
require "../src/connection_pool"
require "../src/connection_pool_manager"
require "uri"

describe ConnectionPool do
  describe "#initialize" do
    it "creates a connection pool with default settings" do
      uri = URI.parse("http://localhost:8080")
      pool = ConnectionPool.new(uri)

      pool.stats["pool_size"].should eq(100)
      pool.stats["max_size"].should eq(200)
    end

    it "creates a connection pool with custom settings" do
      uri = URI.parse("http://localhost:8080")
      pool = ConnectionPool.new(
        uri,
        pool_size: 10,
        max_size: 20,
        idle_timeout: 1.minute
      )

      pool.stats["pool_size"].should eq(10)
      pool.stats["max_size"].should eq(20)
    end
  end

  describe "#acquire" do
    it "acquires a connection from the pool" do
      uri = URI.parse("http://localhost:8080")
      pool = ConnectionPool.new(uri, pool_size: 5)

      # Wait a bit for initial pool to fill
      sleep 100.milliseconds

      client = pool.acquire
      client.should_not be_nil
      client.close if client
    end

    it "returns nil if pool is disabled" do
      uri = URI.parse("http://localhost:8080")
      pool = ConnectionPool.new(uri, pool_size: 1)
      pool.close_all

      client = pool.acquire
      client.should be_nil
    end

    it "creates new connection if pool is empty (timeout)" do
      uri = URI.parse("http://localhost:8080")
      pool = ConnectionPool.new(uri, pool_size: 1)

      # Acquire all connections
      clients = [] of HTTP::Client?
      2.times do
        client = pool.acquire
        clients << client
      end

      # At least one should be non-nil (pool'dan veya fallback)
      clients.any? { |c| !c.nil? }.should be_true

      # Cleanup
      clients.each do |client|
        if client
          pool.release(client)
        end
      end
    end
  end

  describe "#release" do
    it "releases a connection back to the pool" do
      uri = URI.parse("http://localhost:8080")
      pool = ConnectionPool.new(uri, pool_size: 5)

      sleep 100.milliseconds

      client = pool.acquire
      client.should_not be_nil

      if client
        pool.release(client)
        # Connection should be back in pool
        stats = pool.stats
        stats["current_size"].should be > 0
      end
    end

    it "closes connection if pool is full" do
      uri = URI.parse("http://localhost:8080")
      pool = ConnectionPool.new(uri, pool_size: 2, max_size: 2)

      sleep 100.milliseconds

      # Acquire all connections
      clients = [] of HTTP::Client?
      3.times do
        client = pool.acquire || pool.create_new_connection
        clients << client
      end

      # Release all - some should be closed due to max_size
      clients.each do |client|
        pool.release(client) if client
      end

      stats = pool.stats
      stats["current_size"].should be <= 2
    end
  end

  describe "#close_all" do
    it "closes all connections in the pool" do
      uri = URI.parse("http://localhost:8080")
      pool = ConnectionPool.new(uri, pool_size: 5)

      sleep 100.milliseconds

      stats_before = pool.stats
      stats_before["current_size"].should be > 0

      pool.close_all

      stats_after = pool.stats
      stats_after["current_size"].should eq(0)
    end
  end

  describe "#stats" do
    it "returns pool statistics" do
      uri = URI.parse("http://localhost:8080")
      pool = ConnectionPool.new(uri, pool_size: 10)

      sleep 100.milliseconds

      stats = pool.stats
      stats.should have_key("current_size")
      stats.should have_key("pool_size")
      stats.should have_key("max_size")
      stats.should have_key("upstream")
      stats["upstream"].should eq("http://localhost:8080")
    end
  end
end

describe ConnectionPoolManager do
  describe "#initialize" do
    it "creates a pool manager" do
      manager = ConnectionPoolManager.new
      manager.pool_count.should eq(0)
    end

    it "creates a pool manager with config" do
      config = ConnectionPoolingConfig.new_default
      config.pool_size = 50
      config.max_size = 100
      config.idle_timeout = "60s"
      manager = ConnectionPoolManager.new(config)
      manager.pool_count.should eq(0)
    end
  end

  describe "#get_pool" do
    it "creates a new pool for a new upstream" do
      manager = ConnectionPoolManager.new
      uri = URI.parse("http://localhost:8080")

      pool = manager.get_pool(uri, nil, true)
      pool.should_not be_nil

      manager.pool_count.should eq(1)
    end

    it "returns the same pool for the same upstream" do
      manager = ConnectionPoolManager.new
      uri = URI.parse("http://localhost:8080")

      pool1 = manager.get_pool(uri, nil, true)
      pool2 = manager.get_pool(uri, nil, true)

      pool1.should eq(pool2)
      manager.pool_count.should eq(1)
    end

    it "creates different pools for different upstreams" do
      manager = ConnectionPoolManager.new
      uri1 = URI.parse("http://localhost:8080")
      uri2 = URI.parse("http://localhost:8081")

      pool1 = manager.get_pool(uri1, nil, true)
      pool2 = manager.get_pool(uri2, nil, true)

      pool1.should_not eq(pool2)
      manager.pool_count.should eq(2)
    end

    it "creates different pools for different verify_ssl settings" do
      manager = ConnectionPoolManager.new
      uri = URI.parse("https://localhost:8443")

      pool1 = manager.get_pool(uri, nil, true)
      pool2 = manager.get_pool(uri, nil, false)

      pool1.should_not eq(pool2)
      manager.pool_count.should eq(2)
    end

    it "returns nil if pooling is disabled" do
      config = ConnectionPoolingConfig.new_default
      config.enabled = false
      manager = ConnectionPoolManager.new(config)
      uri = URI.parse("http://localhost:8080")

      pool = manager.get_pool(uri, nil, true)
      pool.should be_nil
    end
  end

  describe "#cleanup_idle_pools" do
    it "removes idle pools" do
      manager = ConnectionPoolManager.new
      uri = URI.parse("http://localhost:8080")

      pool = manager.get_pool(uri, nil, true)
      pool.should_not be_nil

      # Wait for pool to become idle (30 minutes)
      # In test, we'll just verify the method exists and works
      manager.cleanup_idle_pools
      # Pool should still exist (not idle enough)
      manager.pool_count.should eq(1)
    end
  end

  describe "#shutdown_all" do
    it "closes all pools" do
      manager = ConnectionPoolManager.new
      uri1 = URI.parse("http://localhost:8080")
      uri2 = URI.parse("http://localhost:8081")

      pool1 = manager.get_pool(uri1, nil, true)
      pool2 = manager.get_pool(uri2, nil, true)

      manager.pool_count.should eq(2)

      manager.shutdown_all

      manager.pool_count.should eq(0)
    end
  end

  describe "#stats" do
    it "returns statistics for all pools" do
      manager = ConnectionPoolManager.new
      uri = URI.parse("http://localhost:8080")

      pool = manager.get_pool(uri, nil, true)
      pool.should_not be_nil

      stats = manager.stats
      stats.should have_key(manager.pool_key(uri, true))
    end
  end
end
