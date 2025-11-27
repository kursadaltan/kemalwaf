#!/usr/bin/env crystal
# Standalone upstream server for CI integration tests

require "http/server"
require "json"

port = (ENV["UPSTREAM_PORT"]? || "8080").to_i

server = HTTP::Server.new do |context|
  context.response.content_type = "application/json"
  context.response.status_code = 200

  body_content = context.request.body.try(&.gets_to_end) || ""

  # Path ve query'yi birleştir
  full_path = context.request.path
  if query = context.request.query
    full_path = "#{full_path}?#{query}"
  end

  # Headers'ı normalize et
  headers_hash = {} of String => String
  context.request.headers.each do |key, values|
    headers_hash[key.downcase] = values.first
  end

  body = {
    method:  context.request.method,
    path:    full_path,
    headers: headers_hash,
    body:    body_content,
  }.to_json

  context.response.print(body)
end

puts "Starting test upstream server on port #{port}..."
spawn { server.listen("0.0.0.0", port) }
puts "Test upstream server started on port #{port}"
# Keep the process running
loop do
  sleep 1.second
end
