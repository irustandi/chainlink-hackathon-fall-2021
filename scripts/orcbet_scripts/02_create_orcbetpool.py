from brownie import OrcBetManager, chain
from scripts.helpful_scripts import (
    get_account,
    get_contract,
)


def create_orcbetpool():
    orcbet_mgr = OrcBetManager[-1]

    orcbet_mgr.addFeed(
        get_contract("eth_usd_price_feed").address,
        {"from": account}
    )

    account = get_account()
    time = chain.time()

    orcbet_mgr.createBetPool(
        get_contract("eth_usd_price_feed").address,
        4000000000000000000000,
        time + 3600,
        {"from": account}
    )

    print(orcbet_mgr.allPools(0))



def main():
    create_orcbetpool()
