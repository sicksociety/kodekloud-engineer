# KodeKloud SSH Automation Script

A bash script to automate SSH key deployment and passwordless sudo configuration for KodeKloud Engineer platform labs. This eliminates repetitive connection and privilege escalation tasks, allowing learners to focus on the actual lab objectives.

## Features

- **Automatic SSH Key Generation**: Creates ED25519 SSH keys if not present
- **SSH Key Deployment**: Copies public keys to all configured servers
- **Passwordless Sudo**: Configures NOPASSWD sudo access on remote hosts
- **Auto-Root Login**: Automatically elevates to root on SSH connection (preserves environment)
- **SSH Aliases**: Creates convenient aliases for quick server access
- **Smart Host Checking**: Validates network connectivity before attempting configuration

## Prerequisites

Required tools (must be installed):
- `ssh`
- `sshpass`
- `ssh-keygen`
- `nc` (netcat) - optional but recommended

## Usage

1. Clone this repository
2. Run the script:
   ```bash
   bash code.sh
   ```
3. Source your bashrc to enable aliases:
   ```bash
   source ~/.bashrc
   ```
4. Connect to any server using the username alias:
   ```bash
   tony      # Connects to stapp01 and auto-elevates to root
   steve     # Connects to stapp02 and auto-elevates to root
   natasha   # Connects to ststor01 and auto-elevates to root
   ```

## Configured Servers

The script configures the following KodeKloud Engineer servers:

| Alias   | Hostname  | IP            | FQDN                              | Description          |
|---------|-----------|---------------|-----------------------------------|----------------------|
| tony    | stapp01   | 172.16.238.10 | stapp01.stratos.xfusioncorp.com   | Nautilus App 1       |
| steve   | stapp02   | 172.16.238.11 | stapp02.stratos.xfusioncorp.com   | Nautilus App 2       |
| banner  | stapp03   | 172.16.238.12 | stapp03.stratos.xfusioncorp.com   | Nautilus App 3       |
| loki    | stlb01    | 172.16.238.14 | stlb01.stratos.xfusioncorp.com    | Nautilus HTTP LBR    |
| peter   | stdb01    | 172.16.239.10 | stdb01.stratos.xfusioncorp.com    | Nautilus DB Server   |
| natasha | ststor01  | 172.16.238.15 | ststor01.stratos.xfusioncorp.com  | Nautilus Storage     |
| clint   | stbkp01   | 172.16.238.16 | stbkp01.stratos.xfusioncorp.com   | Nautilus Backup      |
| groot   | stmail01  | 172.16.238.17 | stmail01.stratos.xfusioncorp.com  | Nautilus Mail        |
| jenkins | jenkins   | 172.16.238.19 | jenkins.stratos.xfusioncorp.com   | Jenkins CI/CD        |

## How It Works

1. **Host Reachability Check**: Tests TCP connectivity on port 22 before attempting configuration
2. **SSH Key Deployment**: Uses `sshpass` to copy SSH public key to remote hosts
3. **Sudo Configuration**: Creates `/etc/sudoers.d/` entries for passwordless sudo
4. **Auto-Root Setup**: Modifies `.bashrc` to automatically elevate to root on login using `sudo su` (preserves environment)
5. **Alias Creation**: Adds convenient SSH aliases to local `.bashrc`

## Why `sudo su` instead of `sudo su -`?

The script uses `sudo su` (without the dash) for auto-root elevation. This approach:
- ✅ Elevates to root automatically on login for **interactive sessions only**
- ✅ Preserves your user environment variables
- ✅ Keeps SSH keys and git config accessible
- ✅ Allows git operations to work properly
- ✅ **Does NOT break scp, sftp, or git over SSH** (only runs for interactive shells)
- ✅ Better for KodeKloud labs that require git access

The script checks `[[ $- == *i* ]]` to ensure auto-root only happens in interactive sessions, preventing issues with file transfers and git operations.

## Network-Level Host Checking

The script uses a smart host checking mechanism that:
- Tests actual SSH port (22) connectivity using netcat or bash TCP
- Completes checks within 3 seconds (fast timeout)
- Distinguishes between network unreachability and authentication issues
- Skips truly unreachable hosts without blocking the workflow

## Customization

To add or modify servers, edit the `SERVERS` array in `code.sh`:

```bash
SERVERS=(
  "hostname|IP|FQDN|user|password|description"
)
```

## Security Notes

⚠️ **This script is designed for lab environments only**
- Passwords are stored in plaintext in the script
- Passwordless sudo grants full root access
- Auto-root elevation happens on every login
- Not suitable for production environments

## Troubleshooting

If a host fails to configure:
1. Verify the host is reachable: `ping <hostname>`
2. Check SSH port is open: `nc -zv <hostname> 22`
3. Verify credentials are correct
4. Check if `sshpass` is installed

## License

MIT License - Free to use and modify for educational purposes.

## Contributing

Feel free to submit issues or pull requests to improve the script.
