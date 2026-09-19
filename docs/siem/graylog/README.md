# Graylog

> **Status**: ⏸️ Explored in 2025, shelved. Not planned. Nothing in this repo targets
> Graylog today.

## Why it was shelved

- It duplicated what OpenSearch + Grafana already provide here (storage, search,
  dashboards) while adding a MongoDB dependency and a second UI to maintain.
- The features that made it attractive — archiving and some alerting — sit behind the
  enterprise licence.
- The project's effort went into the OpenSearch pipeline, the Wazuh dashboards and, on
  the server side, [siem-docker-stack](https://github.com/ChiefGyk3D/siem-docker-stack).

## What exists in history

The original guides (`GRAYLOG_INDEX.md`, `GRAYLOG_SURICATA_SETUP.md`: a Graylog 5.x
install on Ubuntu, a GELF/raw UDP input for the forwarder, extractors for EVE fields and
a starter dashboard) are preserved in git history. Recovery commands are in
[ARCHIVE.md](../../ARCHIVE.md).

## If you want to revive it

The pfSense side needs no changes: the forwarder emits one JSON object per line over
UDP, which a Graylog *Raw/Plaintext UDP* input with a JSON extractor consumes directly.
What a revival would need on the Graylog side:

1. An installation guide for a current Graylog (6.x) with OpenSearch as its index
   backend (Graylog no longer supports Elasticsearch 8+)
2. A content pack: input, JSON extractor, and a stream for `event_type:alert`
3. Field mapping to the [flat EVE fields](../../reference/FIELD_REFERENCE.md) used by
   the Grafana dashboards, if you want the dashboards to work against Graylog's indices
4. A maintainer who runs it

Open a [GitHub Discussion](https://github.com/ChiefGyk3D/pfsense-siem-stack/discussions)
if you do; the comparison of backends is in [COMPARISON.md](../COMPARISON.md).
