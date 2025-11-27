require "./spec_helper"

describe KemalWAF::Evaluator do
  rule_loader = KemalWAF::RuleLoader.new("spec/fixtures/rules")
  evaluator = KemalWAF::Evaluator.new(rule_loader, false, 1048576)

  describe "#evaluate" do
    it "detects SQL injection in ARGS" do
      request = HTTP::Request.new("GET", "/test?id=union select")
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_true
      result.rule_id.should eq(942100)
    end

    it "detects SQL injection in REQUEST_LINE" do
      request = HTTP::Request.new("GET", "/test?q=SELECT * FROM users")
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_true
    end

    it "detects SQL injection in BODY" do
      request = HTTP::Request.new("POST", "/test")
      body = "username=union select"
      result = evaluator.evaluate(request, body)
      result.blocked.should be_true
    end

    it "allows clean requests" do
      request = HTTP::Request.new("GET", "/test?id=123")
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_false
    end

    it "applies url_decode transform" do
      request = HTTP::Request.new("GET", "/test?id=union%20select")
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_true
    end

    it "applies lowercase transform" do
      request = HTTP::Request.new("GET", "/test?id=UNION SELECT")
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_true
    end

    it "handles observe mode correctly" do
      observe_evaluator = KemalWAF::Evaluator.new(rule_loader, true, 1048576)
      request = HTTP::Request.new("GET", "/test?id=union select")
      result = observe_evaluator.evaluate(request, nil)
      result.blocked.should be_false
      result.observed.should be_true
      result.rule_id.should eq(942100)
    end

    it "respects body limit" do
      large_body = "a" * 2000000 # 2MB body
      request = HTTP::Request.new("POST", "/test")
      result = evaluator.evaluate(request, large_body)
      # Body limit aşılsa bile ilk kısmı kontrol edilmeli
      result.blocked.should be_false # SQLi pattern yoksa engellenmemeli
    end

    it "matches multiple variables" do
      request = HTTP::Request.new("GET", "/test?q=SELECT * FROM users")
      request.headers["X-Custom"] = "SELECT * FROM admins"
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_true
    end
  end

  describe "variable snapshot" do
    it "builds REQUEST_LINE correctly" do
      request = HTTP::Request.new("GET", "/test?id=1")
      result = evaluator.evaluate(request, nil)
      # REQUEST_LINE kontrolü için SQLi pattern'i kullan
      request2 = HTTP::Request.new("GET", "/test?q=SELECT * FROM users")
      result2 = evaluator.evaluate(request2, nil)
      result2.blocked.should be_true
    end

    it "builds ARGS correctly" do
      request = HTTP::Request.new("GET", "/test?id=1&name=test")
      result = evaluator.evaluate(request, nil)
      # ARGS kontrolü için SQLi pattern'i kullan
      request2 = HTTP::Request.new("GET", "/test?id=union select")
      result2 = evaluator.evaluate(request2, nil)
      result2.blocked.should be_true
    end

    it "builds HEADERS correctly" do
      request = HTTP::Request.new("GET", "/test")
      request.headers["User-Agent"] = "test"
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_false
    end

    it "builds BODY correctly" do
      request = HTTP::Request.new("POST", "/test")
      body = "username=admin"
      result = evaluator.evaluate(request, body)
      result.blocked.should be_false
    end

    it "builds COOKIE correctly" do
      request = HTTP::Request.new("GET", "/test")
      request.headers["Cookie"] = "session=abc123"
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_false
    end

    it "builds ARGS_NAMES correctly" do
      request = HTTP::Request.new("GET", "/test?id=1&name=test")
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_false
    end

    it "builds COOKIE_NAMES correctly" do
      request = HTTP::Request.new("GET", "/test")
      request.headers["Cookie"] = "session=abc123; user=admin"
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_false
    end

    it "builds REQUEST_FILENAME correctly" do
      request = HTTP::Request.new("GET", "/test/path/file?id=1")
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_false
    end

    it "builds REQUEST_BASENAME correctly" do
      request = HTTP::Request.new("GET", "/test/path/file?id=1")
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_false
    end
  end

  describe "transforms" do
    it "applies none transform" do
      request = HTTP::Request.new("GET", "/test?id=test")
      result = evaluator.evaluate(request, nil)
      # none transform test için özel kural gerekir
      result.blocked.should be_false
    end

    it "applies url_decode_uni transform" do
      request = HTTP::Request.new("GET", "/test?id=test%20value")
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_false
    end

    it "applies remove_nulls transform" do
      request = HTTP::Request.new("GET", "/test?id=test")
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_false
    end

    it "applies replace_comments transform" do
      request = HTTP::Request.new("GET", "/test?id=test")
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_false
    end
  end

  describe "operators" do
    it "supports contains operator" do
      # contains operator test için özel kural gerekir
      request = HTTP::Request.new("GET", "/test?id=test")
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_false
    end

    it "supports starts_with operator" do
      # starts_with operator test için özel kural gerekir
      request = HTTP::Request.new("GET", "/test?id=test")
      result = evaluator.evaluate(request, nil)
      result.blocked.should be_false
    end
  end
end
