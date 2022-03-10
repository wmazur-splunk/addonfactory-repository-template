#
# SPDX-FileCopyrightText: 2021 Splunk, Inc. <sales@splunk.com>
# SPDX-License-Identifier: LicenseRef-Splunk-8-2021
#
#
import os

import pytest

pytest_plugins = "pytester"


def pytest_configure(config):
    config.addinivalue_line("markers", "external: Test search time only")
    config.addinivalue_line("markers", "kubernetes: Test search time only")

