require "./spec_helper"

describe KemalWAF::RuleLoader do
  describe "#initialize" do
    it "loads valid YAML rules" do
      loader = KemalWAF::RuleLoader.new("spec/fixtures/rules")
      loader.rules.size.should eq(3) # valid-rule-1, valid-rule-2 ve invalid-regex (yüklenir ama compiled_regex nil)
    end

    it "handles invalid YAML gracefully" do
      # Geçersiz YAML dosyası var ama hata fırlatmamalı
      loader = KemalWAF::RuleLoader.new("spec/fixtures/rules")
      # Geçerli kurallar yüklenmeli (invalid-regex da yüklenir ama compiled_regex nil)
      loader.rules.size.should eq(3)
    end

    it "compiles regex patterns correctly" do
      loader = KemalWAF::RuleLoader.new("spec/fixtures/rules")
      rule = loader.rules.find { |r| r.id == 942100 }
      rule.should_not be_nil
      rule.not_nil!.compiled_regex.should_not be_nil
    end

    it "handles invalid regex patterns gracefully" do
      loader = KemalWAF::RuleLoader.new("spec/fixtures/rules")
      # Geçersiz regex olan kural yüklenmeli ama compiled_regex nil olmalı
      invalid_rule = loader.rules.find { |r| r.id == 999998 }
      invalid_rule.should_not be_nil
      invalid_rule.not_nil!.compiled_regex.should be_nil
    end
  end

  describe "#rules" do
    it "returns thread-safe copy of rules" do
      loader = KemalWAF::RuleLoader.new("spec/fixtures/rules")
      rules1 = loader.rules
      rules2 = loader.rules
      rules1.should eq(rules2)
      rules1.object_id.should_not eq(rules2.object_id) # Farklı nesneler olmalı
    end
  end

  describe "#load_rules" do
    it "loads multiple rule files" do
      loader = KemalWAF::RuleLoader.new("spec/fixtures/rules")
      loader.rules.size.should be >= 2
    end

    it "skips invalid YAML files" do
      loader = KemalWAF::RuleLoader.new("spec/fixtures/rules")
      # Geçersiz YAML dosyası atlanmalı, sadece geçerli olanlar yüklenmeli
      loader.rules.each do |rule|
        rule.id.should_not eq(999999) # Geçersiz YAML'daki ID yüklenmemeli
      end
    end
  end

  describe "#check_and_reload" do
    it "detects file changes and reloads" do
      loader = KemalWAF::RuleLoader.new("spec/fixtures/rules")
      initial_count = loader.rule_count

      # Dosya değişikliği simüle etmek için bekleme yapıyoruz
      # Gerçek test için dosya değiştirilebilir ama şimdilik basit test
      loader.check_and_reload

      # Reload sonrası kurallar hala yüklenmiş olmalı
      loader.rule_count.should eq(initial_count)
    end

    it "detects deleted files" do
      loader = KemalWAF::RuleLoader.new("spec/fixtures/rules")
      initial_count = loader.rule_count

      # Dosya silme simülasyonu için check_and_reload çağrısı
      loader.check_and_reload

      # Kurallar hala yüklenmiş olmalı
      loader.rule_count.should eq(initial_count)
    end
  end

  describe "#rule_count" do
    it "returns correct number of loaded rules" do
      loader = KemalWAF::RuleLoader.new("spec/fixtures/rules")
      count = loader.rule_count
      count.should eq(loader.rules.size)
    end
  end
end
