#!/bin/sh
# SPDX-FileCopyrightText: 2025 ChiefGyk3D
# SPDX-License-Identifier: MPL-2.0
HOSTNAME=$(hostname)

sysctl dev.cpu | fgrep temperature | tr -d '[:blank:]' | awk -v HOST="$HOSTNAME" -F '[.:]' '{print "temperature,sensor="$2$3",host="HOST" degrees=" $5"."substr($6, 1, length($6)-1)}'
sysctl hw.acpi.thermal | fgrep temperature | tr -d '[:blank:]' | awk -v HOST="$HOSTNAME" -F '[.:]' '{print "temperature,sensor="$4",host="HOST" degrees="$6"." substr($7, 1, length($7)-1)}'
