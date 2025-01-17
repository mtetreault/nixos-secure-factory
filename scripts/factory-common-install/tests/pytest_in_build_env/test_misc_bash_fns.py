
import os
import logging
import subprocess
import pytest

from bash_utils import sanitize_bash_path_out

LOGGER = logging.getLogger(__name__)


def setup_module(module):
    pass


def _get_cfi_libexec_dir():
    return os.path.abspath(os.path.join(
        os.path.dirname(__file__),
        "../../libexec"))

    # return sanitize_bash_path_out(subprocess.check_output(
        # "pkg-nixos-factory-common-install-get-libexec-dir"))


def _get_cfi_sh_module_path(name):
    return os.path.join(_get_cfi_libexec_dir(), name)


def test_get_common_install_libexec_dir():
    ci_libexec_dir = sanitize_bash_path_out(subprocess.check_output(
        "pkg-nixos-common-install-get-libexec-dir")
    )
    LOGGER.info("ci_libexec_dir: %s", ci_libexec_dir)
    assert os.path.exists(ci_libexec_dir)


def test_sandboxed_gpg_version():
    LOGGER.info("hello")
    subprocess.check_output([
        "bash", "-c",
        "true",
        # "{}; {}".format(_get_fi_sh_module_path("tools.sh")),
        "--",
        ""
    ])


def test_sandboxed_gopass_version():
    LOGGER.info("hello")
    subprocess.check_output([
        "bash", "-c",
        "true",
        # "{}; {}".format(_get_fi_sh_module_path("tools.sh")),
        "--",
        ""
    ])
