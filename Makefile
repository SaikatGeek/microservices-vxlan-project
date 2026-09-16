# Multi-datacenter microservices over VXLAN — one entry point for everything.
#
# Run make from this folder, inside the lab container (it needs the AWS CLI
# and the SSH key). Targets that work on the nodes reach them over SSH.
#
#   make help            list every target
#   make all             build everything from nothing and test it
#
# Typical order:
#   make setup-infrastructure     AWS resources + copy this project to the nodes
#   make validate-infrastructure  check the three nodes
#   make setup-vxlan-mesh         bridges, tunnels, docker networks on each node
#   make deploy-services          build images, start all containers
#   make test                     connectivity, services, cross-DC

SHELL := /bin/bash
.DEFAULT_GOAL := help

NODES := 1 2 3

# run <node> <command...> inside that node, in ~/microservices-vxlan-project
REMOTE := bash scripts/remote.sh

# for load-test
REQUESTS ?= 200
PARALLEL ?= 20

.PHONY: help all \
        setup-infrastructure push-project validate-infrastructure \
        setup-vxlan-mesh setup-docker-networks cleanup-vxlan cleanup-infrastructure \
        show-network-status show-routing-table \
        build-all-images deploy-services deploy-dc1-services deploy-dc2-services \
        deploy-dc3-services stop-services start-services cleanup-services \
        test test-connectivity test-services test-cross-dc test-failover \
        load-test health-check show-logs

help: ## Show this list
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | \
	    awk -F':.*## ' '{ printf "  %-26s %s\n", $$1, $$2 }'

all: setup-infrastructure validate-infrastructure setup-vxlan-mesh deploy-services test ## Everything, from nothing to tested

# ============================================================
# Infrastructure
# ============================================================

setup-infrastructure: ## Create VPC, subnets, IGW, SG, key, 3 EC2 nodes, then copy the project to them
	bash scripts/infrastructure/provision.sh
	bash scripts/infrastructure/push-project.sh

push-project: ## Copy this project to the 3 nodes again (after editing files)
	bash scripts/infrastructure/push-project.sh --no-tools

validate-infrastructure: ## Check the 3 nodes: running, SSH, SG, tools, egress, MTU
	bash scripts/infrastructure/verify.sh

setup-vxlan-mesh: ## On each node: bridges, docker network, VXLAN tunnels, fdb peers, firewall
	@for n in $(NODES); do \
	    echo "===== node $$n ====="; \
	    $(REMOTE) $$n bash scripts/infrastructure/overlay-up.sh $$n || exit 1; \
	done

setup-docker-networks: setup-vxlan-mesh ## Docker networks (made by overlay-up.sh with the bridges) and show them
	@for n in $(NODES); do \
	    echo "===== node $$n ====="; \
	    $(REMOTE) $$n bash -c 'docker network ls --filter name=dc 2>/dev/null || sudo docker network ls --filter name=dc'; \
	done

cleanup-vxlan: ## On each node: remove the tunnels, hand-made bridges and firewall rules
	@for n in $(NODES); do \
	    echo "===== node $$n ====="; \
	    $(REMOTE) $$n bash scripts/infrastructure/overlay-down.sh $$n; \
	done

cleanup-infrastructure: ## Delete every AWS resource this project created
	bash scripts/infrastructure/teardown.sh

show-network-status: ## On each node: vxlan links, bridge addresses, fdb peers
	@for n in $(NODES); do \
	    echo "===== node $$n ====="; \
	    $(REMOTE) $$n bash -c 'ip -d -br link show type vxlan; echo; ip -br addr show type bridge; echo; bridge fdb show | grep ^00:00:00:00:00:00'; \
	done

show-routing-table: ## On each node: the kernel routing table
	@for n in $(NODES); do \
	    echo "===== node $$n ====="; \
	    $(REMOTE) $$n ip route; \
	done

# ============================================================
# Services
# ============================================================

build-all-images: ## On each node: build the images its DC needs (node 3 builds all 8)
	@for n in $(NODES); do \
	    $(REMOTE) $$n bash scripts/deployment/deploy-services.sh $$n build || exit 1; \
	done

deploy-services: deploy-dc1-services deploy-dc2-services deploy-dc3-services ## Deploy all three DCs

deploy-dc1-services: ## DC1 on node 1: gateway, user, catalog, order, db, cache
	$(REMOTE) 1 bash scripts/deployment/deploy-services.sh 1 deploy

deploy-dc2-services: ## DC2 on node 2: gateway (backup), payment, notify, order replica, db, cache
	$(REMOTE) 2 bash scripts/deployment/deploy-services.sh 2 deploy

deploy-dc3-services: ## DC3 on node 3: all services as standby, analytics, discovery, db, cache
	$(REMOTE) 3 bash scripts/deployment/deploy-services.sh 3 deploy

stop-services: ## Stop every container, keep them
	@for n in $(NODES); do \
	    echo "===== DC$$n ====="; \
	    $(REMOTE) $$n bash scripts/deployment/deploy-services.sh $$n stop; \
	done

start-services: ## Start stopped containers again
	@for n in $(NODES); do \
	    echo "===== DC$$n ====="; \
	    $(REMOTE) $$n bash scripts/deployment/deploy-services.sh $$n start; \
	done

cleanup-services: ## Remove every container
	@for n in $(NODES); do \
	    echo "===== DC$$n ====="; \
	    $(REMOTE) $$n bash scripts/deployment/deploy-services.sh $$n remove; \
	done

# ============================================================
# Testing
# ============================================================

test: test-connectivity test-services test-cross-dc ## Run the three main test suites

test-connectivity: ## On each node: tunnels, fdb, MTU, firewall, pings to the other DC gateways
	@rc=0; for n in $(NODES); do \
	    $(REMOTE) $$n bash scripts/testing/test-connectivity.sh $$n || rc=1; \
	done; exit $$rc

test-services: ## Each DC: containers running, healthy, answering with the right DC name
	@rc=0; for n in $(NODES); do \
	    $(REMOTE) $$n bash scripts/testing/test-services.sh $$n || rc=1; \
	done; exit $$rc

test-cross-dc: ## Each DC: every gateway route, and container-to-container calls to the other DCs
	@rc=0; for n in $(NODES); do \
	    $(REMOTE) $$n bash scripts/testing/test-cross-dc.sh $$n || rc=1; \
	done; exit $$rc

test-failover: ## Stop DC1 user-nginx, see DC3 take over, start it, see DC1 return
	$(REMOTE) 1 bash scripts/testing/test-failover.sh

load-test: ## Many parallel requests to the DC1 gateway (REQUESTS=200 PARALLEL=20)
	$(REMOTE) 1 bash scripts/testing/load-test.sh 1 $(REQUESTS) $(PARALLEL)

health-check: ## Each DC: state and health of every container
	@for n in $(NODES); do \
	    echo "===== DC$$n ====="; \
	    $(REMOTE) $$n bash scripts/deployment/deploy-services.sh $$n status; \
	done

show-logs: ## Each DC: last lines of every container's log
	@for n in $(NODES); do \
	    echo "===== DC$$n ====="; \
	    $(REMOTE) $$n bash scripts/deployment/deploy-services.sh $$n logs; \
	done
