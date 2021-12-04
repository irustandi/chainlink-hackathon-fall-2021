from brownie import OrcBetManager
from scripts.helpful_scripts import (
    get_account,
    get_contract,
)


def add_feed():
    orcbet_mgr = OrcBetManager[-1]
    account = get_account()

    orcbet_mgr.addFeed(
        get_contract("eth_usd_price_feed").address,
        {"from": account}
    )


def main():
    add_feed()
