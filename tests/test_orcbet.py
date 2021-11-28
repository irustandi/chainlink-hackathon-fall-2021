import pytest
import brownie
from brownie import OrcBetManager, interface, chain
from scripts.helpful_scripts import get_account, get_contract, fund_with_link


@pytest.fixture
def deploy_manager_contract(
    fee_bps,
    min_bet,
):
    account = get_account()
    mgr = OrcBetManager.deploy(
        get_contract("link_token").address,
        fee_bps,
        min_bet,
        {"from": account},
    )

    assert mgr is not None

    return mgr


@pytest.fixture
def deploy_initialized_manager_contract(
    deploy_manager_contract,
    keeper_id,
):
    account = get_account()
    mgr = deploy_manager_contract

    mgr.initialize(
        get_contract("keeper_registry").address,
        keeper_id,
        {"from": account}
    )

    return mgr


@pytest.fixture
def deploy_initialized_manager_contract_with_feed(
    deploy_initialized_manager_contract,
):
    account = get_account()
    mgr = deploy_initialized_manager_contract
    mgr.addFeed(
        get_contract("eth_usd_price_feed").address,
        {"from": account}
    )

    return mgr


@pytest.fixture
def create_pool_contract(
    deploy_initialized_manager_contract_with_feed
):
    mgr = deploy_initialized_manager_contract_with_feed
    time = chain.time()

    mgr.createBetPool(
        get_contract("eth_usd_price_feed").address,
        4000000000000000000000,
        time + 3600,
    )

    pool = mgr.allPools(0)

    return mgr, pool


def test_can_create_initialized_manager(
    deploy_initialized_manager_contract
):
    mgr = deploy_initialized_manager_contract

    assert mgr.initialized()


def test_create_pool_success(
    deploy_initialized_manager_contract_with_feed
):
    bet_account = get_account(1)
    mgr = deploy_initialized_manager_contract_with_feed
    time = chain.time()

    mgr.createBetPool(
        get_contract("eth_usd_price_feed").address,
        4000000000000000000000,
        time + 3600,
        {"from": bet_account}
    )

    pool = mgr.allPools(0)

    assert pool is not None


def test_create_pool_uninitialized_manager(
    deploy_manager_contract
):
    mgr = deploy_manager_contract
    time = chain.time()

    with brownie.reverts():
        tx = mgr.createBetPool(
            get_contract("eth_usd_price_feed").address,
            4000000000000000000000,
            time + 3600,
        )
    
        assert tx.revert_msg == "manager is not initialized yet"


def test_create_pool_no_feed(
    deploy_initialized_manager_contract
):
    mgr = deploy_initialized_manager_contract
    time = chain.time()

    with brownie.reverts():
        tx = mgr.createBetPool(
            get_contract("eth_usd_price_feed").address,
            4000000000000000000000,
            time + 3600,
        )
    
        assert tx.revert_msg == "passing unsupported feed"


def test_add_bet(
    fee_bps,
    create_pool_contract
):
    _, pool_address = create_pool_contract
    pool = interface.IOrcBetPool(pool_address)
    bet_account = get_account(1)

    fund_amount = 1000000000000
    fund_with_link(bet_account, amount=fund_amount)
    assert get_contract('link_token').balanceOf.call(
        bet_account, 
        {'from': bet_account}
    ) >= fund_amount

    bet_above = 10000000000
    bet_below = bet_above

    get_contract('link_token').approve(
        pool_address, 
        bet_above + bet_below, 
        {'from': bet_account})
    pool.addBet(
        bet_above, 
        bet_below,
        {'from': bet_account}
    )

    # check fee
    assert pool.getBetAmountAbove() == (10000. - fee_bps) / 10000 * bet_above
    assert pool.getBetAmountBelow() == (10000. - fee_bps) / 10000 * bet_below