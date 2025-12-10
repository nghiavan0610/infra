#!/bin/bash
# =============================================================================
# Infrastructure Test Script
# =============================================================================
# Validates all configurations without starting services
#
# Usage:
#   ./test.sh              # Run all tests
#   ./test.sh --quick      # Quick syntax check only
#   ./test.sh --verbose    # Show detailed output
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

VERBOSE=${VERBOSE:-false}
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

# Logging
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((TESTS_PASSED++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((TESTS_FAILED++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((TESTS_WARNED++)); }
log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_test() { echo -e "${BLUE}[TEST]${NC} $1"; }

header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# =============================================================================
# Test Functions
# =============================================================================

test_docker() {
    header "Testing Docker"

    if command -v docker &> /dev/null; then
        log_pass "Docker installed: $(docker --version | head -1)"
    else
        log_fail "Docker not installed"
        return 1
    fi

    if docker info &> /dev/null; then
        log_pass "Docker daemon running"
    else
        log_fail "Docker daemon not running"
        return 1
    fi

    if command -v docker compose &> /dev/null; then
        log_pass "Docker Compose installed: $(docker compose version | head -1)"
    else
        log_fail "Docker Compose not installed"
        return 1
    fi
}

test_required_files() {
    header "Testing Required Files"

    local required_files=(
        "setup.sh"
        "stop.sh"
        "status.sh"
        "services.conf"
        "lib/common.sh"
        "lib/database.sh"
        "lib/db-cli.sh"
    )

    for file in "${required_files[@]}"; do
        if [[ -f "$SCRIPT_DIR/$file" ]]; then
            log_pass "Found: $file"
        else
            log_fail "Missing: $file"
        fi
    done

    # Check executables
    local executables=("setup.sh" "stop.sh" "status.sh")
    for file in "${executables[@]}"; do
        if [[ -x "$SCRIPT_DIR/$file" ]]; then
            log_pass "Executable: $file"
        else
            log_warn "Not executable: $file (run: chmod +x $file)"
        fi
    done
}

test_services_conf() {
    header "Testing services.conf"

    if [[ ! -f "$SCRIPT_DIR/services.conf" ]]; then
        log_fail "services.conf not found"
        return 1
    fi

    local service_count=0
    local enabled_count=0

    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue

        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        ((service_count++))

        # Check if service directory exists
        if [[ -d "$SCRIPT_DIR/services/$key" ]]; then
            if [[ "$VERBOSE" == "true" ]]; then
                log_pass "Service exists: $key"
            fi
        else
            log_fail "Service directory missing: services/$key"
        fi

        if [[ "$value" == "true" ]]; then
            ((enabled_count++))
        fi
    done < "$SCRIPT_DIR/services.conf"

    log_pass "Total services in config: $service_count"
    log_info "Enabled services: $enabled_count"
}

test_service_directories() {
    header "Testing Service Directories"

    local services_dir="$SCRIPT_DIR/services"
    local total=0
    local valid=0
    local missing_compose=0
    local missing_env=0

    for service_dir in "$services_dir"/*/; do
        [[ ! -d "$service_dir" ]] && continue

        local service_name=$(basename "$service_dir")
        ((total++))

        # Check docker-compose.yml
        if [[ -f "$service_dir/docker-compose.yml" ]]; then
            ((valid++))
        else
            log_fail "Missing docker-compose.yml: $service_name"
            ((missing_compose++))
            continue
        fi

        # Check .env.example (optional but recommended)
        if [[ ! -f "$service_dir/.env.example" ]] && [[ ! -f "$service_dir/.env" ]]; then
            if [[ "$VERBOSE" == "true" ]]; then
                log_warn "No .env.example: $service_name"
            fi
            ((missing_env++))
        fi
    done

    log_pass "Service directories found: $total"
    log_pass "Valid services (with docker-compose.yml): $valid"
    [[ $missing_env -gt 0 ]] && log_warn "Services without .env.example: $missing_env"
}

test_docker_compose_syntax() {
    header "Testing Docker Compose Syntax"

    local services_dir="$SCRIPT_DIR/services"
    local tested=0
    local passed=0
    local failed=0

    for service_dir in "$services_dir"/*/; do
        [[ ! -d "$service_dir" ]] && continue

        local service_name=$(basename "$service_dir")
        local compose_file="$service_dir/docker-compose.yml"

        [[ ! -f "$compose_file" ]] && continue

        ((tested++))

        # Validate YAML syntax
        if docker compose -f "$compose_file" config --quiet 2>/dev/null; then
            ((passed++))
            if [[ "$VERBOSE" == "true" ]]; then
                log_pass "Valid compose: $service_name"
            fi
        else
            ((failed++))
            log_fail "Invalid compose: $service_name"
            if [[ "$VERBOSE" == "true" ]]; then
                docker compose -f "$compose_file" config 2>&1 | head -5
            fi
        fi
    done

    log_pass "Compose files tested: $tested"
    log_pass "Compose files valid: $passed"
    [[ $failed -gt 0 ]] && log_fail "Compose files invalid: $failed"
}

test_network_consistency() {
    header "Testing Network Consistency"

    local services_dir="$SCRIPT_DIR/services"
    local infra_network=0
    local other_network=0
    local issues=()

    for service_dir in "$services_dir"/*/; do
        [[ ! -d "$service_dir" ]] && continue

        local service_name=$(basename "$service_dir")
        local compose_file="$service_dir/docker-compose.yml"

        [[ ! -f "$compose_file" ]] && continue

        # Check for infra network
        if grep -q "external: true" "$compose_file" && grep -q "name: infra" "$compose_file"; then
            ((infra_network++))
        elif grep -q "infra:" "$compose_file"; then
            ((infra_network++))
        else
            # Some services use their own network (observability, etc.)
            if [[ "$service_name" != "observability" ]] && [[ "$service_name" != "crowdsec" ]]; then
                ((other_network++))
                if [[ "$VERBOSE" == "true" ]]; then
                    log_warn "Not using infra network: $service_name"
                fi
            fi
        fi
    done

    log_pass "Services using infra network: $infra_network"
    [[ $other_network -gt 0 ]] && log_info "Services with custom network: $other_network"
}

test_port_conflicts() {
    header "Testing Port Conflicts"

    local services_dir="$SCRIPT_DIR/services"
    declare -A port_map
    local conflicts=0

    for service_dir in "$services_dir"/*/; do
        [[ ! -d "$service_dir" ]] && continue

        local service_name=$(basename "$service_dir")
        local compose_file="$service_dir/docker-compose.yml"

        [[ ! -f "$compose_file" ]] && continue

        # Extract ports (simple grep, not perfect but catches most)
        while IFS= read -r line; do
            # Match patterns like "8080:8080" or "${PORT:-8080}:8080"
            if [[ "$line" =~ \"([0-9]+):([0-9]+)\" ]] || [[ "$line" =~ \$\{[^}]+:-([0-9]+)\}:([0-9]+) ]]; then
                local port="${BASH_REMATCH[1]}"

                if [[ -n "${port_map[$port]}" ]]; then
                    log_fail "Port conflict: $port used by ${port_map[$port]} and $service_name"
                    ((conflicts++))
                else
                    port_map[$port]="$service_name"
                fi
            fi
        done < <(grep -E "^\s*-\s*[\"']?[\$0-9]" "$compose_file" 2>/dev/null || true)
    done

    if [[ $conflicts -eq 0 ]]; then
        log_pass "No port conflicts detected"
    else
        log_fail "Port conflicts found: $conflicts"
    fi

    log_info "Unique ports configured: ${#port_map[@]}"
}

test_setup_script() {
    header "Testing setup.sh"

    # Bash syntax check
    if bash -n "$SCRIPT_DIR/setup.sh" 2>/dev/null; then
        log_pass "setup.sh syntax valid"
    else
        log_fail "setup.sh syntax error"
        bash -n "$SCRIPT_DIR/setup.sh" 2>&1 | head -5
    fi

    # Check for required functions
    local required_functions=(
        "check_docker"
        "setup_networks"
        "start_service"
        "load_services_conf"
    )

    for func in "${required_functions[@]}"; do
        if grep -q "^${func}()" "$SCRIPT_DIR/setup.sh" || grep -q "^${func} ()" "$SCRIPT_DIR/setup.sh"; then
            log_pass "Function exists: $func"
        else
            log_fail "Function missing: $func"
        fi
    done
}

test_observability_config() {
    header "Testing Observability Configuration"

    local obs_dir="$SCRIPT_DIR/services/observability"

    if [[ ! -d "$obs_dir" ]]; then
        log_fail "Observability directory not found"
        return 1
    fi

    # Check Prometheus config
    if [[ -f "$obs_dir/config/prometheus.yml" ]]; then
        log_pass "prometheus.yml exists"

        # Check for key scrape jobs
        local scrape_jobs=("prometheus" "node-exporter" "cadvisor" "docker-containers")
        for job in "${scrape_jobs[@]}"; do
            if grep -q "job_name: '$job'" "$obs_dir/config/prometheus.yml"; then
                log_pass "Scrape job configured: $job"
            else
                log_warn "Scrape job missing: $job"
            fi
        done
    else
        log_fail "prometheus.yml missing"
    fi

    # Check target files
    local target_files=(
        "postgres.json"
        "redis.json"
        "applications.json"
        "langfuse.json"
    )

    for target in "${target_files[@]}"; do
        if [[ -f "$obs_dir/targets/$target" ]]; then
            log_pass "Target file exists: $target"
        else
            log_warn "Target file missing: $target"
        fi
    done
}

test_env_examples() {
    header "Testing .env.example Files"

    local services_dir="$SCRIPT_DIR/services"
    local checked=0
    local has_required=0

    for service_dir in "$services_dir"/*/; do
        [[ ! -d "$service_dir" ]] && continue

        local service_name=$(basename "$service_dir")
        local env_example="$service_dir/.env.example"

        [[ ! -f "$env_example" ]] && continue

        ((checked++))

        # Check for empty required values that need to be set
        local empty_required=$(grep -E "^[A-Z_]+=$" "$env_example" 2>/dev/null | wc -l)

        if [[ $empty_required -gt 0 ]]; then
            ((has_required++))
            if [[ "$VERBOSE" == "true" ]]; then
                log_info "$service_name has $empty_required required values to configure"
            fi
        fi
    done

    log_pass "Services with .env.example: $checked"
    log_info "Services requiring configuration: $has_required"
}

test_readme_files() {
    header "Testing README Files"

    local services_dir="$SCRIPT_DIR/services"
    local with_readme=0
    local without_readme=0

    for service_dir in "$services_dir"/*/; do
        [[ ! -d "$service_dir" ]] && continue

        local service_name=$(basename "$service_dir")

        if [[ -f "$service_dir/README.md" ]]; then
            ((with_readme++))
        else
            ((without_readme++))
            if [[ "$VERBOSE" == "true" ]]; then
                log_warn "No README: $service_name"
            fi
        fi
    done

    log_pass "Services with README: $with_readme"
    [[ $without_readme -gt 0 ]] && log_warn "Services without README: $without_readme"
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║               INFRASTRUCTURE VALIDATION TEST SUITE                        ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"

    if [[ "${1:-}" == "--quick" ]]; then
        test_docker
        test_required_files
        test_docker_compose_syntax
    else
        test_docker
        test_required_files
        test_services_conf
        test_service_directories
        test_docker_compose_syntax
        test_network_consistency
        test_port_conflicts
        test_setup_script
        test_observability_config
        test_env_examples
        test_readme_files
    fi

    # Summary
    header "Test Summary"

    echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
    echo -e "  ${YELLOW}Warnings:${NC} $TESTS_WARNED"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║                    ALL TESTS PASSED! ✓                                    ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        exit 0
    else
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                    SOME TESTS FAILED! ✗                                   ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        exit 1
    fi
}

main "$@"
