#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Amazon WorkSpaces → CSV Export
# Includes "LastLogonTime" per WorkSpace (LastKnownUserConnectionTimestamp)
# ==============================

# --- Settings (you can override via env vars if you want) ---
REGION_DEFAULT="$(aws configure get region || true)"
REGION="${AWS_REGION:-${REGION_DEFAULT:-us-east-1}}"
CSV_OUT="${CSV_OUT:-workspaces_with_lastlogon.csv}"

echo "Using region: $REGION"
echo "Output file : $CSV_OUT"
echo

# --- 1) Pull all WorkSpaces (auto-paginated by AWS CLI) ---
echo "[1/3] Fetching WorkSpaces..."
WS_JSON="$(mktemp)"
aws workspaces describe-workspaces \
  --region "$REGION" \
  --no-cli-pager \
  > "$WS_JSON"

# Safety check: ensure we got a Workspaces array
if ! jq -e '.Workspaces and (.Workspaces|type=="array")' "$WS_JSON" > /dev/null; then
  echo "No WorkSpaces found (or unexpected response). Exiting."
  exit 0
fi

# --- 2) Pull connection status for all WorkSpaces (handles pagination) ---
echo "[2/3] Fetching connection status (LastKnownUserConnectionTimestamp)..."
CONN_JSON="$(mktemp)"

# The CLI will auto-paginate when no --workspace-ids are provided.
aws workspaces describe-workspaces-connection-status \
  --region "$REGION" \
  --no-cli-pager \
  > "$CONN_JSON"

# --- 3) Join on WorkspaceId and emit CSV ---
echo "[3/3] Building CSV..."

# Header
echo "WorkspaceId,UserName,DirectoryId,ComputerName,IpAddress,OperatingSystem,RunningMode,Status,LastLogonTime" > "$CSV_OUT"

# Use jq to map WorkspaceId -> LastKnownUserConnectionTimestamp, then join
jq -r '
  # Read both inputs: first file is Workspaces; second is ConnectionStatus
  # Build a map of WorkspaceId => LastKnownUserConnectionTimestamp from the second input
  ( input | .WorkspacesConnectionStatus // [] 
    | map({key: .WorkspaceId, value: (.LastKnownUserConnectionTimestamp // null)}) 
    | from_entries
  ) as $connMap
  |
  # Now process the first input (Workspaces list)
  .Workspaces[]
  | {
      WorkspaceId,
      UserName,
      DirectoryId,
      ComputerName: (.ComputerName // null),
      IpAddress: (.IpAddress // null),
      # OS can be in different shapes depending on API/version; try common paths
      OperatingSystem: (.OperatingSystem?.Type // .WorkspaceProperties?.OperatingSystemName // null),
      RunningMode: .WorkspaceProperties.RunningMode,
      Status: .State,
      LastLogonTime: ($connMap[.WorkspaceId] // null)
    }
  | [
      .WorkspaceId,
      .UserName,
      .DirectoryId,
      .ComputerName,
      .IpAddress,
      .OperatingSystem,
      .RunningMode,
      .Status,
      # If null, print empty; you can change to "Never" by replacing (.) with (//"Never")
      .LastLogonTime
    ]
  | @csv
' "$WS_JSON" "$CONN_JSON" >> "$CSV_OUT"

echo
echo "✅ CSV written: $CSV_OUT"
echo "   Preview (first 5 lines):"
head -n 6 "$CSV_OUT" | sed -e 's/^/   /'
echo
echo "Done."

# Cleanup temp files
rm -f "$WS_JSON" "$CONN_JSON"
``