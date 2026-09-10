# Makefile for baobab-iam local development
.PHONY: dev-up dev-down bootstrap test integration-test lint clean

dev-up:
	docker-compose up -d

dev-down:
	docker-compose down

bootstrap:
	docker-compose exec -e BOOTSTRAP_WORKLOAD_CLIENT_SECRET=$$BOOTSTRAP_WORKLOAD_CLIENT_SECRET keycloak /opt/keycloak/bootstrap.sh

test:
	@echo "Running health checks..."
	@curl -s http://localhost:8080/health/ready | grep -q "UP" || (echo "Keycloak not ready" && exit 1)
	@echo "All tests passed."

integration-test:
	./tests/integration/run.sh

lint:
	@echo "Checking YAML files..."
	@yamllint --no-warnings .
	@echo "Checking shell scripts..."
	@shellcheck scripts/*.sh
	@echo "Checking JSON files..."
	@find config -name '*.json' -exec jq empty {} \;

clean:
	docker-compose down -v