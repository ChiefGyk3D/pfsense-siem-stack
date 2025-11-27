# Test Scripts

Validation and testing utilities for the pfSense Suricata Dashboard project.

## Available Tests

### test-multi-interface.sh
Tests multi-interface forwarder functionality.

**Purpose**: Verifies that the forwarder correctly detects and monitors all Suricata instances.

**Usage**:
```bash
./test-multi-interface.sh
```

**Checks**:
- Forwarder process is running
- All Suricata eve.json files are detected
- File descriptors are open for each interface
- GeoIP database is accessible
- Events are being forwarded

### test-panel-compatibility.sh
Tests Grafana panel compatibility with OpenSearch datasource.

**Purpose**: Validates which Grafana panel types work correctly with OpenSearch data.

**Usage**:
```bash
./test-panel-compatibility.sh
```

**Tests**:
- Table panels with logs type
- Pie/donut charts with aggregations
- Stat panels with metrics
- Geomap panels with geo_point data
- Time series visualizations

## Running Tests

### Prerequisites
- pfSense with Suricata running
- Forwarder deployed and active
- SIEM stack operational
- OpenSearch with indexed data

### All Tests
```bash
cd tests
for test in test-*.sh; do
    echo "Running $test..."
    ./"$test"
    echo ""
done
```

## Test Results

Tests output:
- ✓ Success: Green checkmarks with details
- ✗ Failure: Red X with error description
- ⚠ Warning: Yellow warning for non-critical issues

## Adding New Tests

1. Create test script: `test-your-feature.sh`
2. Make executable: `chmod +x test-your-feature.sh`
3. Follow naming convention: `test-*.sh`
4. Document in this README

## Troubleshooting Tests

### test-multi-interface.sh fails
**Issue**: Cannot connect to pfSense
**Fix**: Check SSH access, verify pfSense IP

**Issue**: Forwarder not running
**Fix**: Deploy forwarder with `deploy-pfsense-forwarder.sh`

### test-panel-compatibility.sh fails
**Issue**: No OpenSearch data
**Fix**: Verify forwarder is sending data, check Logstash logs

## Notes

- Tests are non-destructive (read-only)
- Safe to run in production
- Tests do not modify configuration
- Some tests require active traffic for meaningful results
