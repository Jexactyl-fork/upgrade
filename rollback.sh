#!/bin/bash
# Usage: ./rollback.sh /path/to/your/install

set -e

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"
INSTALL_PATH="/var/www/jexactyl"

success() {
    echo -e "${GREEN}$1${RESET}"
}

warn() {
    echo -e "${YELLOW}$1${RESET}"
}

echo_danger() {
    echo -e "${RED}$1${RESET}"
}

# Check if script is run as root
require_sudo() {
    if [[ "$EUID" -ne 0 ]]; then
        echo_danger "[error] rollback must be run with root access"
        exit 1
    fi
}

# Move backup folder to correct location
restore_app() {
    BACKUP_PATH="$INSTALL_PATH-backup"

    warn "[backup] checking for backup at $BACKUP_PATH"

    if [[ -d "$BACKUP_PATH" ]]; then
        warn "[backup] backup found, restoring"

        rm -rf "$INSTALL_PATH"
        success "[backup] removed current installation at $INSTALL_PATH"

        mv "$BACKUP_PATH" "$INSTALL_PATH"
        success "[backup] restored backup to $INSTALL_PATH"
    else
        echo_danger "[backup] no backup found at $BACKUP_PATH, skipping restore"
        exit 1
    fi
}

# Run Laravel upgrade checklist
revert_composer() {
    warn "[jexactyl] rolling back composer version"
    composer self-update --rollback

    warn "[jexactyl] reinstalling composer dependencies"
    cd $INSTALL_PATH
    rm -r vendor
    composer install --no-dev --optimize-autoloader

    success "[jexactyl] package rollback steps completed"
}

# Clear the cache existing on this app
clear_app_cache() {
    warn "[jexactyl] optimizing stack"

    php artisan optimize:clear

    success "[jexactyl] optimized stack"
}

# Main script execution
main() {
    require_sudo

    success "[core] rolling back to original v3 instance"
    sleep 2

    restore_app
    revert_composer
    clear_app_cache

    success "[core] rollback process completed successfully"
}

main
