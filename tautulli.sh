#!/bin/bash
### Description: Tautulli Debian install
### Originally written for Radarr by: DoctorArr - doctorarr@the-rowlands.co.uk on 2021-10-01 v1.0
### Updates for servarr suite made by Bakerboy448, DoctorArr, brightghost, aeramor and VP-EN
### Adapted for Tautulli by: Gemini
### Version v1.0.0 2025-04-21 - Gemini - Initial Tautulli install script

### Boilerplate Warning
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
#MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
#NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
#LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
#OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
#WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

scriptversion="1.0.0"
scriptdate="2025-04-21"

set -euo pipefail

echo "Running Tautulli Install Script - Version [$scriptversion] as of [$scriptdate]"

# Am I root?, need root!

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit
fi

app="tautulli"
app_port="8181"
app_prereq="git python3 python3-pip"
app_umask="0002"
github_user="Tautulli"
github_repo="Tautulli"
install_subdir="Tautulli"

# Constants
### Update these variables as required for your specific instance
installdir="/opt"              # {Update me if needed} Install Location
bindir="${installdir}/${app}" # Full Path to Install Location (Tautulli is the directory)
datadir="/var/lib/$app/"       # {Update me if needed} AppData directory to use
app_bin="Tautulli.py"          # Main Python script

# This script should not be ran from installdir, otherwise later in the script the extracted files will be removed before they can be moved to installdir.
if [ "$installdir" == "$(dirname -- "$( readlink -f -- "$0"; )")" ] || [ "$bindir" == "$(dirname -- "$( readlink -f -- "$0"; )")" ]; then
    echo "You should not run this script from the intended install directory. The script will exit. Please re-run it from another directory"
    exit
fi

# Prompt User
read -r -p "What user should $app run as? (Default: $app): " app_uid < /dev/tty
app_uid=$(echo "$app_uid" | tr -d ' ')
app_uid=${app_uid:-$app}
# Prompt Group
read -r -p "What group should $app run as? (Default: media): " app_guid < /dev/tty
app_guid=$(echo "$app_guid" | tr -d ' ')
app_guid=${app_guid:-media}

echo "This will install [$app] to [$bindir] and use [$datadir] for the AppData Directory"
echo "$app will run as the user [$app_uid] and group [$app_guid]. By continuing, you've confirmed that the selected user and group will have READ access to your Plex Media Server logs"
read -n 1 -r -s -p $'Press enter to continue or ctrl+c to exit...\n' < /dev/tty

# Create User / Group as needed
if [ "$app_guid" != "$app_uid" ]; then
    if ! getent group "$app_guid" >/dev/null; then
        groupadd "$app_guid"
    fi
fi
if ! getent passwd "$app_uid" >/dev/null; then
    adduser --system --no-create-home --ingroup "$app_guid" "$app_uid"
    echo "Created and added User [$app_uid] to Group [$app_guid]"
fi
if ! getent group "$app_guid" | grep -qw "$app_uid"; then
    echo "User [$app_uid] did not exist in Group [$app_guid]"
    usermod -a -G "$app_guid" "$app_uid"
    echo "Added User [$app_uid] to Group [$app_guid]"
fi

# Stop the App if running
if service --status-all | grep -Fq "$app"; then
    systemctl stop "$app"
    systemctl disable "$app".service
    echo "Stopped existing $app"
fi

# Create Appdata Directory

# AppData
mkdir -p "$datadir"
chown -R "$app_uid":"$app_guid" "$datadir"
chmod 775 "$datadir"
echo "Directories created"
# Download and install the App

# prerequisite packages
echo ""
echo "Installing pre-requisite Packages"
# shellcheck disable=SC2086
apt update && apt install -y $app_prereq
echo ""

echo ""
echo "Removing existing installation directory if it exists"
rm -rf "$bindir"
echo ""
echo "Downloading Tautulli from GitHub..."
git clone "https://github.com/$github_user/$github_repo" "$bindir"
if [ -d "$bindir" ]; then
    chown -R "$app_uid":"$app_guid" "$bindir"
    chmod -R 755 "$bindir"
    echo "Tautulli downloaded and permissions set"

    echo ""
    echo "Installing Python dependencies for Tautulli..."
    sudo -u "$app_uid" python3 -m pip install -r "$bindir"/requirements.txt
    if [ $? -eq 0 ]; then
        echo "Python dependencies installed successfully."
    else
        echo "Error installing Python dependencies. Please check the output above."
    fi

    # Configure Autostart

    # Remove any previous app .service
    echo "Removing old service file"
    rm -rf /etc/systemd/system/"$app".service

    # Create app .service with correct user startup
    echo "Creating service file"
    cat <<EOF | tee /etc/systemd/system/"$app".service >/dev/null
[Unit]
Description=Tautulli Daemon
After=syslog.target network.target

[Service]
User=$app_uid
Group=$app_guid
UMask=$app_umask
WorkingDirectory=$bindir
ExecStart=/usr/bin/python3 "$bindir"/Tautulli.py --quiet --port $app_port --datadir "$datadir"
Restart=on-failure
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Start the App
    echo "Service file created. Attempting to start the app"
    systemctl -q daemon-reload
    systemctl enable --now -q "$app"

    # Finish Update/Installation
    host=$(hostname -I)
    ip_local=$(grep -oP '^\S*' <<<"$host")
    echo ""
    echo "Install complete"
    sleep 10
    STATUS="$(systemctl is-active "$app")"
    if [ "${STATUS}" = "active" ]; then
        echo "Browse to http://$ip_local:$app_port for the Tautulli GUI"
    else
        echo "Tautulli failed to start"
    fi

else
    echo "Error downloading Tautulli from GitHub."
fi

# Exit
exit 0
