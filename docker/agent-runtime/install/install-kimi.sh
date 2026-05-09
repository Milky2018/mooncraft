#!/usr/bin/env bash
set -euo pipefail

export PATH="/root/.local/bin:${PATH}"

curl -LsSf https://code.kimi.com/install.sh | bash
cp -a /root/.local/share/uv/tools/kimi-cli /opt/kimi-cli
cp -a /root/.local/share/uv/python /opt/uv-python

python_path="$(find /opt/uv-python -path '*/bin/python3.13' -type f | head -n 1)"
test -n "$python_path"

ln -sf "$python_path" /opt/kimi-cli/bin/python
ln -sf python /opt/kimi-cli/bin/python3
ln -sf python /opt/kimi-cli/bin/python3.13
sed -i '1s|^#!.*$|#!/opt/kimi-cli/bin/python|' \
  /opt/kimi-cli/bin/kimi \
  /opt/kimi-cli/bin/kimi-cli
ln -sf /opt/kimi-cli/bin/kimi /usr/local/bin/kimi
ln -sf /opt/kimi-cli/bin/kimi-cli /usr/local/bin/kimi-cli
chmod -R a+rX /opt/kimi-cli /opt/uv-python

kimi --version
