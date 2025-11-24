#!/bin/sh
# SPDX-FileCopyrightText: 2025 ChiefGyk3D
# SPDX-License-Identifier: MPL-2.0
/usr/local/sbin/unbound-control -c /var/unbound/unbound.conf $* | grep -vE 'thread[0-9]+'
