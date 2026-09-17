# Optional, opt-in sandbox image with a real security-tool arsenal installed
# — the thing that makes ryvx/prompts.py's TOOL_CATALOG stop being
# aspirational. The default image (python:3.12-slim, see sandbox.py) stays
# small and fast for the common case of reviewing your own source; build
# this one when you want agents to actually be able to run nmap/sqlmap/
# semgrep/nuclei/etc via run_shell.
#
# Build:   docker build -t ryvx-sandbox -f containers/Dockerfile .
# Use it:  export RYVX_SANDBOX_IMAGE=ryvx-sandbox
#
# Base: debian:bookworm-slim (Debian stable), not a rolling/testing distro —
# see docs/superpowers/specs/2026-07-27-sandbox-minimal-base-design.md for
# why (this project already got burned once by a rolling curated distro's
# version drift, on the RE-sandbox image). Every tool here is a headless CLI
# binary, so none of Kali's actual differentiators (desktop env, curated
# interactive workflows) were ever in play.

FROM debian:bookworm-slim

# Packaged in Debian bookworm's own apt repo — no pinning needed beyond
# whatever bookworm ships, since bookworm itself is a fixed stable release.
RUN apt-get update && apt-get install -y --no-install-recommends \
        nmap masscan whatweb gobuster ffuf dirb \
        sqlmap hydra \
        perl libjson-perl libxml-writer-perl git curl unzip ca-certificates \
        python3 python3-pip jq \
    && rm -rf /var/lib/apt/lists/*

# Pure-Perl, not packaged in bookworm — pinned tag, no build step needed.
RUN git clone --branch 2.6.0 --depth 1 https://github.com/sullo/nikto /opt/nikto \
    && ln -s /opt/nikto/program/nikto.pl /usr/local/bin/nikto \
    && chmod +x /opt/nikto/program/nikto.pl

# Static/code analysis — not reliably packaged in apt, pip is the stable path.
# Must run *before* the pinned-binary install below: semgrep's dependency
# chain pulls in the Python `httpx` package, which installs its own
# console-script at /usr/local/bin/httpx — if pip ran last it would silently
# clobber ProjectDiscovery's httpx binary.
#
# D-2 (2026-08-09): --require-hashes against a real, pip-compiled lockfile
# instead of an unpinned `pip3 install semgrep bandit` -- a compromised or
# typosquatted release of any of semgrep/bandit's own transitive deps used
# to be able to silently land in every future sandbox image build.
# requirements-sandbox.txt is generated (not hand-edited) via:
#   pip-compile --generate-hashes --output-file=requirements-sandbox.txt containers/requirements-sandbox.in
# run inside a matching debian:bookworm-slim/python3 container -- resolving
# on a different Python version can silently pick incompatible pins.
COPY requirements-sandbox.txt /tmp/requirements-sandbox.txt
RUN pip3 install --no-cache-dir --break-system-packages --require-hashes -r /tmp/requirements-sandbox.txt \
    && rm /tmp/requirements-sandbox.txt

# Not packaged in bookworm at all — pinned GitHub release binaries, no Go
# toolchain needed in the final image.
#
# Every archive is SHA-256 verified against the checksum published in its own
# upstream release before it is unpacked. A pinned version tag on its own does
# not help if a release asset is re-uploaded under the same tag, or if the
# download is tampered with in transit, and this layer used to trust whatever
# bytes curl handed back. That is the same gap --require-hashes already closes
# for the pip layer above, and that vm_image_fetch.py closes for the
# RE-sandbox guest image.
#
# Sums are taken from each project's own published *_checksums.txt for the
# pinned tag. Bump them in the same commit as a version bump; the build fails
# loudly on drift rather than installing an unexpected binary.
RUN set -eux; \
    fetch() { curl -fsSL -o "/tmp/$1" "$2"; echo "$3  /tmp/$1" | sha256sum -c -; }; \
    fetch nuclei.zip        https://github.com/projectdiscovery/nuclei/releases/download/v3.11.0/nuclei_3.11.0_linux_amd64.zip                   dc238d6040813e14fc30514dac5a2eb1b430c694f3ca99eee2a5097e55076283; \
    fetch subfinder.zip     https://github.com/projectdiscovery/subfinder/releases/download/v2.14.0/subfinder_2.14.0_linux_amd64.zip             6529294788f56a20ed96a9b70e71f8f3c247f1d6104ba1e2c2e9e58d8a32c6cb; \
    fetch httpx.zip         https://github.com/projectdiscovery/httpx/releases/download/v1.10.0/httpx_1.10.0_linux_amd64.zip                     63eac4dcd6e5c9867c94765fdaaf66e7b4eeae3474a1f06e600e266a1c81a53e; \
    fetch gitleaks.tar.gz   https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz                      551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb; \
    fetch trufflehog.tar.gz https://github.com/trufflesecurity/trufflehog/releases/download/v3.96.0/trufflehog_3.96.0_linux_amd64.tar.gz          7105f1cd6577f058a9e39d0578f1a99c8a1e481e4d3512cd8a09acfe22a0fdc0; \
    unzip -qo /tmp/nuclei.zip    -d /usr/local/bin nuclei; \
    unzip -qo /tmp/subfinder.zip -d /usr/local/bin subfinder; \
    unzip -qo /tmp/httpx.zip     -d /usr/local/bin httpx; \
    tar -xzf /tmp/gitleaks.tar.gz   -C /usr/local/bin gitleaks; \
    tar -xzf /tmp/trufflehog.tar.gz -C /usr/local/bin trufflehog; \
    rm -f /tmp/nuclei.zip /tmp/subfinder.zip /tmp/httpx.zip /tmp/gitleaks.tar.gz /tmp/trufflehog.tar.gz; \
    chmod +x /usr/local/bin/nuclei /usr/local/bin/subfinder /usr/local/bin/httpx /usr/local/bin/gitleaks /usr/local/bin/trufflehog

# Keep nuclei's template DB current at build time (agents can re-run
# `nuclei -update-templates` themselves for a fresher set at scan time)
RUN nuclei -update-templates || true

WORKDIR /workspace
CMD ["sleep", "infinity"]
