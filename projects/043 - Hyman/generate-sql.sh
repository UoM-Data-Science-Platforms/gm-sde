#!/bin/bash

# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Linux/mac bash script to stitch the template SQL into the extraction SQL │
# │ It also constructs a README.md file for the project listing all code     │
# │ sets used in the creation of the SQL and any other useful info too       │
# └──────────────────────────────────────────────────────────────────────────┘


PROJECT_REL_PATH=$(dirname "$0")
PROJECT_FULL_PATH="$(pwd)/$PROJECT_REL_PATH"
REPO_ROOT_FULL_PATH="$PROJECT_FULL_PATH/../../"
MAIN_SCRIPT_FULL_PATH="$REPO_ROOT_FULL_PATH/scripts/main.js"

# move to repo root
cd "$REPO_ROOT_FULL_PATH"

# Call npm install to ensure up to date
npm i --quiet

# Return to project
cd "${PROJECT_FULL_PATH}"

node "$MAIN_SCRIPT_FULL_PATH" stitch

read -p "Press [Enter] to continue..."