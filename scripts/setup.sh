#!/usr/bin/env bash
# Creates a scratch org, deploys the project, and loads the sample learners and certifications.
# Usage: ./scripts/setup.sh [org-alias]
set -euo pipefail
ALIAS="${1:-deactivation-challenge}"

sf org create scratch --definition-file config/project-scratch-def.json --alias "$ALIAS" --set-default --duration-days 14
sf project deploy start --target-org "$ALIAS"
sf org assign permset --name Badge_Challenge_Admin --target-org "$ALIAS"

# Users and Certifications are loaded in separate transactions: inserting a setup object (User)
# and a regular object in the same transaction causes a MIXED_DML_OPERATION error.
sf apex run --file scripts/apex/seed-users.apex --target-org "$ALIAS"
sf apex run --file scripts/apex/seed-certs.apex --target-org "$ALIAS"

echo "Done. Open the org with: sf org open --target-org $ALIAS"
