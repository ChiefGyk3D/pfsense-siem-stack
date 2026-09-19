# Test Scripts

Validation and testing utilities for the pfSense Suricata Dashboard project.

There are two kinds of tests. All commands below are run **from the repository
root**.

- **Unit tests** (`tests/python/`) — run anywhere, no infrastructure needed; CI runs these.
- **Integration test scripts** (`tests/test-*.sh`) — need a `config.env` in the
  repository root plus SSH access to a live deployment (pfSense and the SIEM
  server), so they are **not** run in CI.

## Unit Tests (pytest)

### tests/python/test_forwarder.py

Unit tests for the core logic of `scripts/forward-suricata-eve.py`:

- Log-rotation handling (inode change and truncation) using temp files
- GeoIP enrichment, including the no-database fallback (maxminddb is not required —
  the GeoIP reader is stubbed, so no GeoIP database is needed)
- UDP event forwarding format (mocked socket)

**Usage:**
```bash
python3 -m pip install pytest   # one-time
python3 -m pytest tests/python/ -v
```

These run in CI on every push via `.github/workflows/lint.yml`.

## Integration Tests

Both scripts source `config.env` from the repository root for `SIEM_HOST`,
`PFSENSE_HOST`, `PFSENSE_USER`, ports and Grafana credentials.

### tests/test-multi-interface.sh
Tests multi-interface forwarder functionality.

**Purpose**: Verifies that the forwarder correctly detects and monitors all Suricata instances.

**Usage**:
```bash
./tests/test-multi-interface.sh              # uses PFSENSE_HOST from config.env
./tests/test-multi-interface.sh <PFSENSE_IP> # or pass the host explicitly
```

**Checks**:
- Forwarder process is running
- All Suricata eve.json files are detected
- File descriptors are open for each interface
- GeoIP database is accessible
- Events are being forwarded

### tests/test-panel-compatibility.sh
Tests Grafana panel compatibility with OpenSearch datasource.

**Purpose**: Validates which Grafana panel types work correctly with OpenSearch data.

**Usage**:
```bash
./tests/test-panel-compatibility.sh
```

**Tests**:
- Table panels with logs type
- Pie/donut charts with aggregations
- Stat panels with metrics
- Geomap panels with geo_point data
- Time series visualizations

## Running the Integration Tests

### Prerequisites
- `config.env` present in the repository root
- Key-based SSH access to pfSense as `PFSENSE_USER`
- pfSense with Suricata running and the forwarder deployed (`./setup.sh`)
- SIEM stack operational, with indexed data in OpenSearch

### All Tests
```bash
for test in tests/test-*.sh; do
    echo "Running $test..."
    "$test"
    echo ""
done
```

## Test Results

Tests output:
- ✓ Success: Green checkmarks with details
- ✗ Failure: Red X with error description
- ⚠ Warning: Yellow warning for non-critical issues

## Adding New Tests

1. Create the script: `tests/test-your-feature.sh`
2. Make it executable: `chmod +x tests/test-your-feature.sh`
3. Follow the naming convention `test-*.sh` and source `config.env` the way the existing scripts do
4. Document it in this README

## Troubleshooting Tests

### test-multi-interface.sh fails
**Issue**: Cannot connect to pfSense
**Fix**: Check SSH access and `PFSENSE_HOST` / `PFSENSE_USER` in `config.env`

**Issue**: Forwarder not running
**Fix**: Deploy the forwarder with `./setup.sh`, or `ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh start'`

### test-panel-compatibility.sh fails
**Issue**: No OpenSearch data
**Fix**: Verify the forwarder is sending data and check the Logstash logs; see [docs/troubleshooting/TROUBLESHOOTING.md](../docs/troubleshooting/TROUBLESHOOTING.md)

## Notes

- Tests are non-destructive (read-only)
- Safe to run in production
- Tests do not modify configuration
- Some tests require active traffic for meaningful results
