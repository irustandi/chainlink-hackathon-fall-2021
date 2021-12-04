from brownie import OrcBetManager, config, network
from scripts.helpful_scripts import (
    get_account,
    get_contract,
)


def initialize_keeper():
    orcbet_mgr = OrcBetManager[-1]
    account = get_account()

    orcbet_mgr.initialize(
        get_contract("keeper_registry").address,
        config["networks"][network.show_active()].get("keeperID", 1),
        {"from": account},
    )

    print(f"Manager keeperId: {orcbet_mgr.keeperId()}")
    print(f"Manager initialized: {orcbet_mgr.initialized()}")

    return orcbet_mgr


def main():
    initialize_keeper()
