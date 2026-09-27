.PHONY: bootstrap validate scan scan-gate bench userns maintenance timers timers-remove

bootstrap:
	bash scripts/bootstrap.sh

validate:
	bash scripts/validate-template.sh

scan:
	bash scripts/scan-images.sh

scan-gate:
	bash scripts/scan-images.sh --gate-critical

bench:
	sudo bash scripts/run-docker-bench.sh

userns:
	sudo bash scripts/verify-userns-remap.sh

maintenance:
	bash scripts/docker-image-maintenance.sh --pull --prune-dangling

timers:
	sudo bash scripts/install-systemd-timers.sh

timers-remove:
	sudo bash scripts/uninstall-systemd-timers.sh
