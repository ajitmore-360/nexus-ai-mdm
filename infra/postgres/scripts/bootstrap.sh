#!/bin/bash

set -e

echo "===================================="
echo "Azile AI MDM BOOTSTRAP"
echo "===================================="

./reset.sh

./migrate.sh

./verify.sh

echo "===================================="
echo "Bootstrap completed"
echo "===================================="