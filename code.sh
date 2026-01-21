#!/usr/bin/env bash
set -euo pipefail

KEY_PATH="$HOME/.ssh/id_ed25519"
BASHRC="$HOME/.bashrc"

# Server list: hostname|IP|FQDN|user|password|description
SERVERS=(
  "stapp01|172.16.238.10|stapp01.stratos.xfusioncorp.com|tony|Ir0nM@n|Nautilus App 1"
  "stapp02|172.16.238.11|stapp02.stratos.xfusioncorp.com|steve|Am3ric@|Nautilus App 2"
  "stapp03|172.16.238.12|stapp03.stratos.xfusioncorp.com|banner|BigGr33n|Nautilus App 3"
  "stlb01|172.16.238.14|stlb01.stratos.xfusioncorp.com|loki|Mischi3f|Nautilus HTTP LBR"
  "stdb01|172.16.239.10|stdb01.stratos.xfusioncorp.com|peter|Sp!dy|Nautilus DB Server"
  "ststor01|172.16.238.15|ststor01.stratos.xfusioncorp.com|natasha|Bl@kW|Nautilus Storage Server"
  "stbkp01|172.16.238.16|stbkp01.stratos.xfusioncorp.com|clint|H@wk3y3|Nautilus Backup Server"
  "stmail01|172.16.238.17|stmail01.stratos.xfusioncorp.com|groot|Gr00T123|Nautilus Mail Server"
  "jenkins|172.16.238.19|jenkins.stratos.xfusioncorp.com|jenkins|j@rv!s|Jenkins Server for CI/CD"
)

# Ensure required tools exist
for cmd in ssh sshpass ssh-keygen; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ $cmd not found. Install it first."; exit 1; }
done

# Create SSH key if missing
if [[ ! -f "$KEY_PATH" ]]; then
  echo "🔑 Creating SSH key..."
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -q -C "auto-generated-$(date +%Y%m%d)"
  chmod 600 "$KEY_PATH"
  chmod 644 "$KEY_PATH.pub"
else
  echo "✅ SSH key already exists: $KEY_PATH"
fi

# Function to check if host is reachable at network level (TCP port 22)
is_host_up() {
    local host=$1
    local port=22
    local timeout=3
    
    # Try netcat if available (primary method)
    if command -v nc >/dev/null 2>&1; then
        timeout "$timeout" nc -z -w2 "$host" "$port" >/dev/null 2>&1
        return $?
    elif command -v timeout >/dev/null 2>&1; then
        # Fallback: use bash TCP test with timeout
        timeout "$timeout" bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null
        return $?
    else
        # Last resort: basic bash TCP test (no timeout)
        (cat < /dev/null > /dev/tcp/$host/$port) 2>/dev/null
        return $?
    fi
}

# Deploy SSH keys, set NOPASSWD sudo, and enable auto-root
FAILED_HOSTS=()
SUCCESS_HOSTS=()

for ENTRY in "${SERVERS[@]}"; do
    IFS="|" read -r HOSTNAME IP FQDN USER PASSWORD DESC <<< "$ENTRY"
    echo "------------------------------------------"
    echo "📡 Processing $USER@$FQDN ($DESC)..."
    
    # Check if host is reachable via SSH
    if ! is_host_up "$FQDN"; then
        echo "❌ $FQDN is unreachable. Skipping..."
        FAILED_HOSTS+=("$FQDN")
        continue
    fi
    
    echo "✅ $FQDN is reachable."
    
    # Copy SSH key (skip if already exists)
    echo "🔑 Ensuring SSH key is deployed..."
    sshpass -p "$PASSWORD" ssh-copy-id \
        -i "$KEY_PATH.pub" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        "$USER@$FQDN" &>/dev/null || true
    
    # Setup passwordless sudo and auto-root
    echo "⚡ Configuring passwordless sudo and auto-root..."
    
    # Create the remote script with proper variable substitution
    REMOTE_CMD=$(cat <<EOF
set -e

# Configure passwordless sudo
echo '$PASSWORD' | sudo -S sh -c 'cat > /etc/sudoers.d/$USER <<SUDOERS_CONTENT
$USER ALL=(ALL) NOPASSWD: ALL
SUDOERS_CONTENT
'

# Set proper permissions
echo '$PASSWORD' | sudo -S chmod 440 /etc/sudoers.d/$USER

# Verify sudoers syntax
echo '$PASSWORD' | sudo -S visudo -c -f /etc/sudoers.d/$USER

# Test passwordless sudo
sudo -n whoami > /dev/null 2>&1 && echo "✓ Passwordless sudo verified"

# Add auto-root to .bashrc if not already present
if ! grep -q "exec sudo su" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc <<'BASHRC_END'

# Auto-elevate to root (added by automation script)
# Only for interactive shells to avoid breaking scp/sftp/git
if [ \$(id -u) -ne 0 ] && [[ \$- == *i* ]]; then
    exec sudo su
fi
BASHRC_END
    echo "✓ Auto-root added to .bashrc"
else
    echo "✓ Auto-root already in .bashrc"
fi

echo "Configuration complete for $USER"
EOF
)
    
    if sshpass -p "$PASSWORD" ssh \
           -o ConnectTimeout=10 \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           "$USER@$FQDN" "$REMOTE_CMD"
    then
        echo "✅ $USER@$FQDN configuration complete."
        SUCCESS_HOSTS+=("$USER@$FQDN")
    else
        echo "⚠️  Failed to configure $USER@$FQDN."
        FAILED_HOSTS+=("$FQDN (config)")
    fi
done

echo "------------------------------------------"
echo "🎉 SSH key deployment complete."

# Backup existing .bashrc
if [[ -f "$BASHRC" ]]; then
    cp "$BASHRC" "${BASHRC}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Add aliases to ~/.bashrc
echo "" >> "$BASHRC"
echo "# Auto-generated SSH aliases - $(date)" >> "$BASHRC"

for ENTRY in "${SERVERS[@]}"; do
    IFS="|" read -r HOSTNAME IP FQDN USER PASSWORD DESC <<< "$ENTRY"
    ALIAS_CMD="alias $USER='ssh -o StrictHostKeyChecking=no $USER@$FQDN'"
    
    if ! grep -q "^alias $USER=" "$BASHRC"; then
        echo "➕ Adding alias: $USER"
        echo "$ALIAS_CMD  # $DESC" >> "$BASHRC"
    else
        echo "ℹ️  Alias '$USER' already exists"
    fi
done

echo "✅ Aliases added to $BASHRC"
echo ""
echo "📋 Summary:"
echo "  ✓ SSH keys deployed"
echo "  ✓ Passwordless sudo configured"
echo "  ✓ Auto-root on login enabled"
echo "  ✓ SSH aliases created"
echo ""

if [ ${#SUCCESS_HOSTS[@]} -gt 0 ]; then
    echo "✅ Successfully configured hosts:"
    printf '  - %s\n' "${SUCCESS_HOSTS[@]}"
    echo ""
fi

if [ ${#FAILED_HOSTS[@]} -gt 0 ]; then
    echo "⚠️  Failed hosts:"
    printf '  - %s\n' "${FAILED_HOSTS[@]}"
    echo ""
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 NEXT STEPS - Run this command to activate aliases:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "   source ~/.bashrc"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📖 USAGE EXAMPLES:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "   tony      # SSH to stapp01 and auto-elevate to root"
echo "   steve     # SSH to stapp02 and auto-elevate to root"
echo "   natasha   # SSH to ststor01 and auto-elevate to root"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 TIP: Using 'sudo su' to preserve environment for git access"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
