#!/bin/bash
# Usage: ./main.sh /path/to/your/install dbname

set -e

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"
INSTALL_PATH="/var/www/jexactyl"
DB_NAME="jexactyl"

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
        echo_danger "[error] upgrade must be run with root access"
        exit 1
    fi
}

# Use either default install path or a provided argument
parse_arguments() {
    if [[ -n "$1" ]]; then
        INSTALL_PATH="$1"
    elif [[ -n "$2" ]]; then
        DB_NAME="$2"
    fi
    cd "$INSTALL_PATH" || { echo_danger "[path] failed to enter install path: $INSTALL_PATH"; exit 1; }
}

# Check PHP Version and exit if below 8.1
check_php_version() {
    warn "[preflight] checking php version is above 8.1"
    PHP_VERSION=$(php -r 'echo PHP_VERSION;')
    echo "Current PHP version: $PHP_VERSION"

    PHP_MAJOR=$(echo "$PHP_VERSION" | cut -d. -f1)
    PHP_MINOR=$(echo "$PHP_VERSION" | cut -d. -f2)

    if [[ "$PHP_MAJOR" -lt 8 ]] || { [[ "$PHP_MAJOR" -eq 8 ]] && [[ "$PHP_MINOR" -lt 1 ]]; }; then
        echo_danger "PHP version must be 8.1 or higher. Exiting."
        exit 1
    fi

    success "[preflight] using php v$PHP_VERSION"
}

# Install Laravel PHP dependencies
install_dependencies() {
    warn "[dependencies] refreshing apt repositories"
    apt update

    warn "[dependencies] adding prerequisite packages"
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg

    warn "[dependencies] adding potentially missing php packages"
    apt install -y php-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip}
}

# Backup current Jexactyl instance
backup_app() {
    warn "[backup] creating local backup for restore point"

    BACKUP_DIR="${INSTALL_PATH}-backup"
    cp -r "$INSTALL_PATH" "$BACKUP_DIR"

    success "[backup] created"

    warn "[backup] creating database backup"
    mysqldump $DB_NAME > $BACKUP_DIR/jexactyl.sql

    success "[backup] database backup created"
}

# Put the Panel into maintenance mode
enable_maintenance_mode() {
    warn "[jexactyl] entering maintenance mode"

    cd $INSTALL_PATH
    php artisan down

    success "[jexactyl] system is down for upgrade"
}

# Download the new release file
download_files() {
    warn "[download] removing old files"
    rm -r $INSTALL_PATH/app $INSTALL_PATH/resources $INSTALL_PATH/database $INSTALL_PATH/public $INSTALL_PATH/bootstrap $INSTALL_PATH/config $INSTALL_PATH/routes

    warn "[download] getting new release with curl"
    curl -Lo panel.tar.gz https://github.com/Jexactyl/Jexactyl/releases/download/v4.0.0-beta6/panel.tar.gz

    warn "[download] extracting archive"
    tar -xzvf panel.tar.gz

    success "[download] complete"
}

# Completely reinstall Composer packages
reinstall_composer_packages() {
    warn "[composer] reinstalling packages"
    rm -r vendor
    composer install --no-dev --optimize-autoloader

    success "[composer] complete"
}

# Run Laravel upgrade checklist
run_laravel_upgrade_steps() {
    warn "[jexactyl] clearing cache"
    php artisan optimize:clear

    warn "[jexactyl] updating composer packages"
    composer self-update
    composer install --no-dev --optimize-autoloader

    success "[jexactyl] setup steps completed"
}

# Transform database and migrate to v4
migrate_database() {
    warn "[database] removing old data and tables, please wait..."

    ENV_PATH="${1:-$INSTALL_PATH/.env}"

    if [[ ! -f "$ENV_PATH" ]]; then
        danger "[database] failed to find login details in $INSTALL_PATH/.env"
        return 1
    fi

    # Extract credentials from .env
    DB_HOST=$(grep -E '^DB_HOST=' "$ENV_PATH" | cut -d '=' -f2)
    DB_PORT=$(grep -E '^DB_PORT=' "$ENV_PATH" | cut -d '=' -f2)
    DB_NAME=$(grep -E '^DB_DATABASE=' "$ENV_PATH" | cut -d '=' -f2)
    DB_USER=$(grep -E '^DB_USERNAME=' "$ENV_PATH" | cut -d '=' -f2)
    DB_PASS=$(grep -E '^DB_PASSWORD=' "$ENV_PATH" | cut -d '=' -f2-)

    # Set defaults if variables are empty
    DB_PORT="${DB_PORT:-3306}"

    success "[database] authenticated - type admin password to continue"
    success "[database] (you may be able to leave this blank by pressing enter): "

    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT 1;"
    success "[database] connected successfully, attempting edits"

    warn "[database] (1 of 5): drop old tickets table"
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "DROP TABLE tickets; DROP TABLE ticket_messages;" || true

    warn "[database] (2 of 5): drop old theme table"
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "DROP TABLE theme;" || true

    warn "[database] (3 of 5): remove old node deployable column"
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "ALTER TABLE nodes DROP COLUMN deployable;" || true

    warn "[database] attempting database migration"
    php artisan migrate --seed
}

# Add necessary filesystem and webserver permissions
add_webserver_permissions() {
    warn "[permissions] assigning webserver permission"
    chown -R www-data:www-data $INSTALL_PATH/storage

    warn "[permissions] assigning filesystem permission"
    chmod -R 755 storage/* bootstrap/cache/

    success "[permissions] complete"
}

disable_maintenance_mode() {
    warn "[jexactyl] disabling maintenance mode"

    cd $INSTALL_PATH
    php artisan up

    success "[jexactyl] system is available"
}

# Main script execution
main() {
    require_sudo
    parse_arguments "$1"

    success "[core] beginning upgrade process"
    sleep 2

    check_php_version
    install_dependencies
    backup_app
    enable_maintenance_mode
    download_files
    reinstall_composer_packages
    migrate_database
    run_laravel_upgrade_steps
    add_webserver_permissions
    disable_maintenance_mode

    success "[core] upgrade process completed successfully"
}

main "$@"
