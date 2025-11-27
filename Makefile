check-libinjection:
	@echo "🔍 LibInjection kontrol ediliyor..."
	@if [ -f "lib/libinjection/libinjection.a" ]; then \
		echo "✅ LibInjection static library bulundu (lib/libinjection/libinjection.a)"; \
	elif pkg-config --exists libinjection 2>/dev/null; then \
		echo "✅ LibInjection sistem kütüphanesi bulundu"; \
	elif [ -f "/usr/local/lib/libinjection.a" ] || [ -f "/usr/local/lib/libinjection.dylib" ]; then \
		echo "✅ LibInjection /usr/local/lib'de bulundu"; \
	else \
		echo "⚠️  LibInjection bulunamadı!"; \
		echo "   LibInjection olmadan libinjection_sqli ve libinjection_xss çalışmayacak"; \
	fi

build: check-libinjection
	./build.sh

run:
	./run.sh

# Test komutları
test: test-unit

test-unit:
	@echo "🧪 Unit testleri çalıştırılıyor..."
	@if [ -f "lib/libinjection/libinjection.a" ]; then \
		ABS_LIB_PATH="$$(pwd)/lib/libinjection"; \
		crystal spec --link-flags "-L$$ABS_LIB_PATH -linjection" spec/rule_loader_spec.cr spec/evaluator_spec.cr spec/proxy_client_spec.cr spec/metrics_spec.cr spec/ip_filter_spec.cr spec/rate_limiter_spec.cr; \
	elif pkg-config --exists libinjection 2>/dev/null; then \
		LIBINJECTION_FLAGS=$$(pkg-config --libs --cflags libinjection); \
		crystal spec --link-flags "$$LIBINJECTION_FLAGS" spec/rule_loader_spec.cr spec/evaluator_spec.cr spec/proxy_client_spec.cr spec/metrics_spec.cr spec/ip_filter_spec.cr spec/rate_limiter_spec.cr; \
	elif [ -f "/usr/local/lib/libinjection.a" ] || [ -f "/usr/local/lib/libinjection.dylib" ]; then \
		crystal spec --link-flags "-L/usr/local/lib -linjection" spec/rule_loader_spec.cr spec/evaluator_spec.cr spec/proxy_client_spec.cr spec/metrics_spec.cr spec/ip_filter_spec.cr spec/rate_limiter_spec.cr; \
	else \
		echo "⚠️  LibInjection bulunamadı, libinjection operator'ları olmadan test ediliyor..."; \
		crystal spec spec/rule_loader_spec.cr spec/evaluator_spec.cr spec/proxy_client_spec.cr spec/metrics_spec.cr spec/ip_filter_spec.cr spec/rate_limiter_spec.cr; \
	fi

test-integration:
	@echo "🧪 Integration testleri çalıştırılıyor..."
	@echo "⚠️  WAF server'ın çalışıyor olması gerekiyor (port 3000)"
	@echo "   WAF'ı başlatmak için: make run-waf"
	@if [ -f "lib/libinjection/libinjection.a" ]; then \
		ABS_LIB_PATH="$$(pwd)/lib/libinjection"; \
		crystal spec --link-flags "-L$$ABS_LIB_PATH -linjection" spec/integration/; \
	elif pkg-config --exists libinjection 2>/dev/null; then \
		LIBINJECTION_FLAGS=$$(pkg-config --libs --cflags libinjection); \
		crystal spec --link-flags "$$LIBINJECTION_FLAGS" spec/integration/; \
	elif [ -f "/usr/local/lib/libinjection.a" ] || [ -f "/usr/local/lib/libinjection.dylib" ]; then \
		crystal spec --link-flags "-L/usr/local/lib -linjection" spec/integration/; \
	else \
		crystal spec spec/integration/; \
	fi

test-all: test-unit test-integration

# WAF server'ı test modunda başlat (integration testler için)
run-waf:
	@echo "🚀 WAF server test modunda başlatılıyor..."
	@if [ -f bin/kemal-waf ]; then \
		export RULE_DIR=spec/fixtures/rules && \
		export UPSTREAM=http://localhost:8080 && \
		export OBSERVE=false && \
		./bin/kemal-waf & \
		echo "✅ WAF server başlatıldı (PID: $$!)"; \
		echo "   Durdurmak için: pkill -f kemal-waf"; \
	else \
		echo "❌ Binary bulunamadı. Önce 'make build' çalıştırın."; \
		exit 1; \
	fi

stop-waf:
	@echo "🛑 WAF server durduruluyor..."
	@pkill -f kemal-waf || echo "WAF server zaten durdurulmuş"

# Eski test komutu (backward compatibility)
test-waf:
	./tools/test.waf.sh

load-test:
	./tools/load_test.sh

waf-tester:
	./tools/waf_tester.py

# Docker komutları
up:
	docker-compose up -d

down:
	docker-compose down

restart:
	docker-compose restart

logs:
	docker-compose logs -f

format:
	crystal tool format