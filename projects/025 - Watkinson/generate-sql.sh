#!/bin/bash

# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Linux/mac bash script to stitch the template SQL into the extraction SQL │
# │ It also constructs a README.md file for the project listing all code     │
# │ sets used in the creation of the SQL and any other useful info too       │
# └──────────────────────────────────────────────────────────────────────────┘


# move to batch dir 
FULL_PATH=$(realpath "$0")
PROJECT_DIR="$(dirname "$FULL_PATH")"
cd "${PROJECT_DIR}"

# move to project root
cd ../..

# Call npm install to ensure up to date
npm i --quiet

# Return to project root
cd "${PROJECT_DIR}"

node ../../scripts/main.js stitch

read -p "Press [Enter] to continue..."