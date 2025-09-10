#!/bin/bash

# Test Runner for Nextcloud + OnlyOffice Installation Scripts
# 
# This script runs each installation script line by line with validation:
# - Executes one command at a time
# - Shows the command before running it
# - Waits for user confirmation
# - Validates the result
# - Runs built-in tests after each script
# - Stops on any failure

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nextcloud-test.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

header() {
    echo -e "${CYAN}${BOLD}$1${NC}" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Show command and ask for confirmation
show_and_confirm() {
    local command="$1"
    local line_num="$2"
    local script_name="$3"
    
    echo ""
    header "Script: $script_name | Line: $line_num"
    echo -e "${YELLOW}Command:${NC} $command"
    echo ""
    
    read -p "Execute this command? (y/n/s/q): " -n 1 -r
    echo
    
    case $REPLY in
        y|Y) return 0 ;;
        s|S) 
            info "Skipping command"
            return 1 
            ;;
        q|Q) 
            info "Quitting test runner"
            exit 0 
            ;;
        *) 
            warning "Command not executed"
            return 1 
            ;;
    esac
}

# Execute command with monitoring
execute_command() {
    local command="$1"
    local timeout_seconds="${2:-60}"
    
    log "Executing: $command"
    
    # Start command in background and monitor
    timeout "$timeout_seconds" bash -c "$command" || {
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            error "Command timed out after $timeout_seconds seconds"
        else
            error "Command failed with exit code: $exit_code"
        fi
        return $exit_code
    }
    
    success "Command completed successfully"
    return 0
}

# Parse and run script line by line
run_script_interactive() {
    local script_path="$1"
    local script_name=$(basename "$script_path")
    
    if [[ ! -f "$script_path" ]]; then
        error "Script not found: $script_path"
        return 1
    fi
    
    header "Testing Script: $script_name"
    info "Press 'y' to execute, 's' to skip, 'q' to quit"
    echo ""
    
    local line_num=0
    local in_function=false
    local function_name=""
    
    # Read script line by line
    while IFS= read -r line; do
        ((line_num++))
        
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Skip function definitions and variable assignments
        if [[ "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\) ]]; then
            in_function=true
            function_name=$(echo "$line" | sed 's/().*//')
            info "Found function: $function_name"
            continue
        fi
        
        # Skip function closing braces
        if [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*$ ]]; then
            in_function=false
            continue
        fi
        
        # Skip variable assignments and control structures
        if [[ "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*= ]] || \
           [[ "$line" =~ ^[[:space:]]*(if|for|while|case|function) ]] || \
           [[ "$line" =~ ^[[:space:]]*(then|else|elif|fi|do|done|esac) ]] || \
           [[ "$line" =~ ^[[:space:]]*set[[:space:]] ]]; then
            continue
        fi
        
        # Extract actual commands (remove leading whitespace)
        local command=$(echo "$line" | sed 's/^[[:space:]]*//')
        
        # Skip if it's not a command
        [[ -z "$command" ]] && continue
        
        # Show command and get confirmation
        if show_and_confirm "$command" "$line_num" "$script_name"; then
            # Determine timeout based on command type
            local timeout=60
            if [[ "$command" =~ (apt|wget|curl|certbot) ]]; then
                timeout=300
            fi
            
            # Execute the command
            if ! execute_command "$command" "$timeout"; then
                error "Command failed at line $line_num"
                echo ""
                read -p "Continue anyway? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    return 1
                fi
            fi
        fi
        
    done < "$script_path"
    
    success "Script $script_name completed"
    return 0
}

# Built-in test for system prep
test_system_prep() {
    header "Testing System Preparation"
    
    local tests_passed=0
    local tests_total=5
    
    # Test 1: Check if packages are installed
    if dpkg -l | grep -q nginx; then
        success "✓ Nginx installed"
        ((tests_passed++))
    else
        error "✗ Nginx not installed"
    fi
    
    # Test 2: Check if PHP is installed
    if command -v php &> /dev/null; then
        success "✓ PHP installed"
        ((tests_passed++))
    else
        error "✗ PHP not installed"
    fi
    
    # Test 3: Check if MariaDB is installed
    if systemctl list-unit-files | grep -q mariadb; then
        success "✓ MariaDB installed"
        ((tests_passed++))
    else
        error "✗ MariaDB not installed"
    fi
    
    # Test 4: Check if firewall is configured
    if ufw status | grep -q "Status: active"; then
        success "✓ Firewall active"
        ((tests_passed++))
    else
        error "✗ Firewall not active"
    fi
    
    # Test 5: Check if directories exist
    if [[ -d "/srv/nextcloud-data" ]]; then
        success "✓ Data directory created"
        ((tests_passed++))
    else
        error "✗ Data directory not created"
    fi
    
    info "System Prep Test: $tests_passed/$tests_total passed"
    return $((tests_total - tests_passed))
}

# Built-in test for database setup
test_database_setup() {
    header "Testing Database Setup"
    
    local tests_passed=0
    local tests_total=4
    
    # Test 1: MariaDB running
    if systemctl is-active --quiet mariadb; then
        success "✓ MariaDB running"
        ((tests_passed++))
    else
        error "✗ MariaDB not running"
    fi
    
    # Test 2: PostgreSQL running
    if systemctl is-active --quiet postgresql; then
        success "✓ PostgreSQL running"
        ((tests_passed++))
    else
        error "✗ PostgreSQL not running"
    fi
    
    # Test 3: Redis running
    if systemctl is-active --quiet redis-server; then
        success "✓ Redis running"
        ((tests_passed++))
    else
        error "✗ Redis not running"
    fi
    
    # Test 4: Database credentials exist
    if [[ -f "/root/nextcloud-db-credentials.txt" ]]; then
        success "✓ Database credentials saved"
        ((tests_passed++))
    else
        error "✗ Database credentials not found"
    fi
    
    info "Database Setup Test: $tests_passed/$tests_total passed"
    return $((tests_total - tests_passed))
}

# Built-in test for Nextcloud installation
test_nextcloud_install() {
    header "Testing Nextcloud Installation"
    
    local tests_passed=0
    local tests_total=4
    
    # Test 1: Nextcloud directory exists
    if [[ -d "/var/www/nextcloud" ]]; then
        success "✓ Nextcloud directory exists"
        ((tests_passed++))
    else
        error "✗ Nextcloud directory not found"
    fi
    
    # Test 2: Config file exists
    if [[ -f "/var/www/nextcloud/config/config.php" ]]; then
        success "✓ Nextcloud configured"
        ((tests_passed++))
    else
        error "✗ Nextcloud not configured"
    fi
    
    # Test 3: OCC command works
    if sudo -u www-data php /var/www/nextcloud/occ status --no-warnings &> /dev/null; then
        success "✓ Nextcloud OCC working"
        ((tests_passed++))
    else
        error "✗ Nextcloud OCC not working"
    fi
    
    # Test 4: Admin credentials saved
    if [[ -f "/root/nextcloud-admin-credentials.txt" ]]; then
        success "✓ Admin credentials saved"
        ((tests_passed++))
    else
        error "✗ Admin credentials not found"
    fi
    
    info "Nextcloud Install Test: $tests_passed/$tests_total passed"
    return $((tests_total - tests_passed))
}

# Run all tests
run_all_tests() {
    local scripts=(
        "01_system_prep.sh:test_system_prep"
        "02_database_setup.sh:test_database_setup"
        "03_nextcloud_install.sh:test_nextcloud_install"
    )
    
    for script_info in "${scripts[@]}"; do
        local script_name="${script_info%%:*}"
        local test_function="${script_info##*:}"
        local script_path="$SCRIPT_DIR/$script_name"
        
        header "Running $script_name"
        
        if run_script_interactive "$script_path"; then
            success "Script $script_name completed successfully"
            
            # Run built-in test
            if command -v "$test_function" &> /dev/null; then
                if "$test_function"; then
                    success "All tests passed for $script_name"
                else
                    error "Some tests failed for $script_name"
                    read -p "Continue to next script? (y/N): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        return 1
                    fi
                fi
            fi
        else
            error "Script $script_name failed"
            return 1
        fi
        
        echo ""
        read -p "Press Enter to continue to next script..."
        echo ""
    done
    
    success "All scripts completed successfully!"
}

# Main execution
main() {
    check_root
    
    header "Interactive Script Testing Framework"
    info "This will run each script line by line with confirmation"
    info "Log file: $LOG_FILE"
    echo ""
    
    read -p "Start interactive testing? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Testing cancelled"
        exit 0
    fi
    
    run_all_tests
}

# Run main function
main "$@"
