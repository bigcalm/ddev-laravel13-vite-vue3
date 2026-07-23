#!/usr/bin/env bash
set -euo pipefail

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${DIM}[info]${NC} $*"; }
step()  { echo -e "\n${BOLD}[$1/$TOTAL]${NC} $2"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
fail()  { echo -e "${RED}✗${NC} $*"; exit 1; }

PROJECT_NAME="${1:-}"
TOTAL=7

if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: $0 <project-name>"
    echo ""
    echo "Creates a new Laravel 13 + Vue starter kit project inside ./<project-name>"
    echo "using DDEV for the local development environment."
    exit 1
fi

if ! [[ "$PROJECT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    fail "Project name must only contain letters, numbers, hyphens, and underscores."
fi

if [ -d "$PROJECT_NAME" ]; then
    fail "Directory '$PROJECT_NAME' already exists."
fi

command -v ddev &>/dev/null || fail "ddev is not installed — see https://ddev.com/get-started"
command -v docker &>/dev/null || fail "docker is not installed."

docker info &>/dev/null || fail "docker daemon is not running."

info "Project: $PROJECT_NAME"

# --- Step 1 ---
step 1 "Scaffold DDEV project"
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"
ddev config --project-type=laravel --docroot=public
cat >> .ddev/config.yaml << 'EOF'
web_extra_exposed_ports:
  - name: vite
    container_port: 5173
    http_port: 5172
    https_port: 5173
EOF
ok "DDEV configured with Vite port mapping"

# --- Step 2 ---
step 2 "Install Laravel CLI inside DDEV"
ddev start
ddev composer global require laravel/installer
ok "Laravel CLI installed"

# --- Step 3 ---
step 3 "Create Laravel project with Vue starter kit"
ddev exec \$HOME/.composer/vendor/bin/laravel new tmp-app --vue --npm
ddev exec "cp -r tmp-app/. /var/www/html/ && rm -rf tmp-app"
ddev exec "sed -i 's|APP_URL=http://localhost:8000|APP_URL=https://${PROJECT_NAME}.ddev.site|' .env"
ok "Laravel project scaffolded"

# --- Step 4 ---
step 4 "Configure database for DDEV MariaDB"
ddev exec sed -i \
  -e 's/DB_CONNECTION=sqlite/DB_CONNECTION=mariadb/' \
  -e 's/# DB_HOST=127.0.0.1/DB_HOST=db/' \
  -e 's/# DB_PORT=3306/DB_PORT=3306/' \
  -e 's/# DB_DATABASE=laravel/DB_DATABASE=db/' \
  -e 's/# DB_USERNAME=root/DB_USERNAME=db/' \
  -e 's/# DB_PASSWORD=/DB_PASSWORD=db/' \
  .env
ddev artisan migrate
ok "Database configured and migrated"

# --- Step 5 ---
step 5 "Configure Vite for DDEV"
cat > vite.config.ts << 'VITEEOF'
import inertia from '@inertiajs/vite';
import { wayfinder } from '@laravel/vite-plugin-wayfinder';
import tailwindcss from '@tailwindcss/vite';
import vue from '@vitejs/plugin-vue';
import laravel from 'laravel-vite-plugin';
import { bunny } from 'laravel-vite-plugin/fonts';
import { defineConfig } from 'vite';

export default defineConfig({
    plugins: [
        laravel({
            input: ['resources/css/app.css', 'resources/js/app.ts'],
            refresh: true,
            fonts: [
                bunny('Instrument Sans', {
                    weights: [400, 500, 600],
                }),
            ],
        }),
        inertia(),
        tailwindcss(),
        vue({
            template: {
                transformAssetUrls: {
                    base: null,
                    includeAbsolute: false,
                },
            },
        }),
        wayfinder({
            formVariants: true,
        }),
    ],
    server: {
        host: "0.0.0.0",
        port: 5173,
        strictPort: true,
        origin: `${process.env.DDEV_PRIMARY_URL_WITHOUT_PORT}:5173`,
        allowedHosts: ['.ddev.site'],
        cors: {
            origin: /https?:\/\/([A-Za-z0-9\-\.]+)?(\.ddev\.site)(?::\d+)?$/,
        },
    },
});
VITEEOF
ok "Vite configured for DDEV"

# --- Step 6 ---
step 6 "Build frontend assets"
ddev npm run build
ok "Frontend built"

# --- Optional ---
echo ""
read -rp "$(echo -e "${YELLOW}Start Laravel dev server? [Y/n]:${NC} ")" yn
if [[ ! "$yn" =~ ^[Nn]$ ]]; then
    ddev composer run dev
fi

# --- Done ---
step 7 "Finished"
echo ""
echo -e "${GREEN}${BOLD}Project '${PROJECT_NAME}' is ready!${NC}"
echo ""
echo "  ${BOLD}Start development:${NC}"
echo "    cd ${PROJECT_NAME}"
echo "    ddev npm run dev"
echo ""
echo "  ${BOLD}Open in browser:${NC}"
echo "    https://${PROJECT_NAME}.ddev.site"
