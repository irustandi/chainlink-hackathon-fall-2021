from brownie import OrcBetManager, config, network
from scripts.helpful_scripts import (
    get_account,
    get_contract,
)


def deploy_orcbetmanager():
    account = get_account()
    print(f"On network {network.show_active()}")

    orcbet_mgr = OrcBetManager.deploy(
        get_contract("link_token").address,
        100,
        1000000000000000000,
        {"from": account},
        publish_source=config["networks"][network.show_active()].get("verify", False),
    )

    print(f"Manager feeBps: {orcbet_mgr.feeBps()}")
    print(f"Manager minBet: {orcbet_mgr.minBet()}")

    return orcbet_mgr


def main():
    deploy_orcbetmanager()
