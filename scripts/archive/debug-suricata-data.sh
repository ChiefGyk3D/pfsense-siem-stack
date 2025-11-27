#!/bin/bash

# Enable stdout debugging to see raw Suricata data

echo "Checking what raw data looks like..."
echo ""

# Check a few documents to see the structure
curl -s "http://localhost:9200/suricata-*/_search?size=3" | jq '.hits.hits[]._source' | head -50

echo ""
echo "================================"
echo ""
echo "The issue is that suricata.eve is empty."
echo "Let me check the Suricata EVE log format on pfSense..."
echo ""
