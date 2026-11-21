.PHONY: preflight validate build start start-metadata status test report stop

preflight:
	bash scripts/preflight.sh

validate:
	bash scripts/validate.sh

build:
	docker compose build --pull falco

start:
	bash scripts/start.sh

start-metadata:
	bash scripts/start.sh --docker-metadata

status:
	bash scripts/status.sh

test:
	bash scripts/test-alerts.sh

report:
	bash scripts/report.sh

stop:
	bash scripts/stop.sh
