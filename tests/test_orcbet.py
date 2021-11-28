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
    deploy_initialized_manager_contract_with_feed,
    pool_threshold,
    pool_duration,
):
    mgr = deploy_initialized_manager_contract_with_feed
    time = chain.time()
    start_time = time
    finish_time = time + pool_duration

    mgr.createBetPool(
        get_contract("eth_usd_price_feed").address,
        pool_threshold,
        finish_time,
    )

    pool = mgr.allPools(0)

    return mgr, pool, start_time, finish_time


@pytest.fixture
def create_pool_contract_with_two_bets(
    create_pool_contract,
    pool_duration,
):
    mgr, pool_address, start_time, finish_time = create_pool_contract
    pool = interface.IOrcBetPool(pool_address)

    fund_amount = 1000000000000
    bet_account1 = get_account(1)
    fund_with_link(bet_account1, amount=fund_amount)

    bet_account2 = get_account(2)
    fund_with_link(bet_account2, amount=fund_amount)

    bet_above = 10000000000
    bet_below = 0

    get_contract('link_token').approve(
        pool_address, 
        bet_above + bet_below, 
        {'from': bet_account1})
    pool.addBet(
        bet_above, 
        bet_below,
        {'from': bet_account1}
    )

    bet_above = 0
    bet_below = 10000000000

    get_contract('link_token').approve(
        pool_address, 
        bet_above + bet_below, 
        {'from': bet_account2})
    pool.addBet(
        bet_above, 
        bet_below,
        {'from': bet_account2}
    )

    chain.mine(timedelta=pool_duration)

    return mgr, pool, start_time, finish_time


@pytest.fixture
def create_pool_contract_with_four_bets(
    create_pool_contract,
    pool_duration,
):
    mgr, pool_address, start_time, finish_time = create_pool_contract
    pool = interface.IOrcBetPool(pool_address)

    fund_amount = 1000000000000
    bet_account1 = get_account(1)
    fund_with_link(bet_account1, amount=fund_amount)

    bet_account2 = get_account(2)
    fund_with_link(bet_account2, amount=fund_amount)

    bet_account3 = get_account(3)
    fund_with_link(bet_account3, amount=fund_amount)

    bet_account4 = get_account(4)
    fund_with_link(bet_account4, amount=fund_amount)

    bet_above = 10000000000
    bet_below = 0

    get_contract('link_token').approve(
        pool_address, 
        bet_above + bet_below, 
        {'from': bet_account1})
    pool.addBet(
        bet_above, 
        bet_below,
        {'from': bet_account1}
    )

    bet_above = 0
    bet_below = 10000000000

    get_contract('link_token').approve(
        pool_address, 
        bet_above + bet_below, 
        {'from': bet_account2})
    pool.addBet(
        bet_above, 
        bet_below,
        {'from': bet_account2}
    )

    bet_above = 20000000000
    bet_below = 0

    get_contract('link_token').approve(
        pool_address, 
        bet_above + bet_below, 
        {'from': bet_account3})
    pool.addBet(
        bet_above, 
        bet_below,
        {'from': bet_account3}
    )

    bet_above = 0
    bet_below = 30000000000

    get_contract('link_token').approve(
        pool_address, 
        bet_above + bet_below, 
        {'from': bet_account4})
    pool.addBet(
        bet_above, 
        bet_below,
        {'from': bet_account4}
    )

    chain.mine(timedelta=pool_duration)

    return mgr, pool, start_time, finish_time


def test_can_create_initialized_manager(
    deploy_initialized_manager_contract
):
    mgr = deploy_initialized_manager_contract

    assert mgr.initialized()


def test_create_pool_success(
    deploy_initialized_manager_contract_with_feed,
    pool_threshold,
    pool_duration
):
    bet_account = get_account(1)
    mgr = deploy_initialized_manager_contract_with_feed
    time = chain.time()

    mgr.createBetPool(
        get_contract("eth_usd_price_feed").address,
        pool_threshold,
        time + pool_duration,
        {"from": bet_account}
    )

    pool = interface.IOrcBetPool(mgr.allPools(0))

    assert pool.active()
    assert pool.getBetAmountAbove() == 0
    assert pool.getBetAmountBelow() == 0


def test_create_pool_uninitialized_manager(
    deploy_manager_contract,
    pool_threshold,
    pool_duration,
):
    mgr = deploy_manager_contract
    time = chain.time()

    with brownie.reverts():
        tx = mgr.createBetPool(
            get_contract("eth_usd_price_feed").address,
            pool_threshold,
            time + pool_duration,
        )
    
        assert tx.revert_msg == "manager is not initialized yet"


def test_create_pool_no_feed(
    deploy_initialized_manager_contract,
    pool_threshold,
    pool_duration,
):
    mgr = deploy_initialized_manager_contract
    time = chain.time()

    with brownie.reverts():
        tx = mgr.createBetPool(
            get_contract("eth_usd_price_feed").address,
            pool_threshold,
            time + pool_duration,
        )
    
        assert tx.revert_msg == "passing unsupported feed"


def test_add_bet(
    fee_bps,
    create_pool_contract
):
    _, pool_address, _, _ = create_pool_contract
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


def test_finish_pool_equal(
    create_pool_contract_with_two_bets,
    round_id,
    pool_threshold,
):
    _, pool, _, finish_time = create_pool_contract_with_two_bets

    feed = get_contract('eth_usd_price_feed')
    keeper_registry_address = get_contract('keeper_registry').address
    feed.updateRoundData(
        round_id,
        pool_threshold,
        finish_time,
        finish_time,
    )

    bet_above = pool.getBetAmountAbove()
    bet_below = pool.getBetAmountBelow()

    assert pool.canFinish()

    tx = pool.finish({'from': keeper_registry_address})
    assert len(tx.events['Transfer']) == 2

    bet_account_above = get_account(1)
    bet_account_below = get_account(2)

    for event in tx.events:
        if event.name == 'Transfer':
            if event['to'] == bet_account_above:
                assert event['value'] == bet_above
            if event['to'] == bet_account_below:
                assert event['value'] == bet_below


def test_finish_pool_above(
    create_pool_contract_with_two_bets,
    round_id,
    pool_threshold,
    pool_value_delta,
):
    _, pool, _, finish_time = create_pool_contract_with_two_bets

    feed = get_contract('eth_usd_price_feed')
    keeper_registry_address = get_contract('keeper_registry').address
    feed.updateRoundData(
        round_id,
        pool_threshold + pool_value_delta,
        finish_time,
        finish_time,
    )

    bet_above = pool.getBetAmountAbove()
    bet_below = pool.getBetAmountBelow()

    assert pool.canFinish()

    tx = pool.finish({'from': keeper_registry_address})
    assert len(tx.events['Transfer']) == 1

    bet_account_above = get_account(1)

    for event in tx.events:
        if event.name == 'Transfer':
            assert event['to'] == bet_account_above
            assert event['value'] == bet_above + bet_below


def test_finish_pool_below(
    create_pool_contract_with_two_bets,
    round_id,
    pool_threshold,
    pool_value_delta,
):
    _, pool, _, finish_time = create_pool_contract_with_two_bets

    feed = get_contract('eth_usd_price_feed')
    keeper_registry_address = get_contract('keeper_registry').address
    feed.updateRoundData(
        round_id,
        pool_threshold - pool_value_delta,
        finish_time,
        finish_time,
    )

    bet_above = pool.getBetAmountAbove()
    bet_below = pool.getBetAmountBelow()

    assert pool.canFinish()

    tx = pool.finish({'from': keeper_registry_address})
    assert len(tx.events['Transfer']) == 1

    bet_account_below = get_account(2)

    for event in tx.events:
        if event.name == 'Transfer':
            assert event['to'] == bet_account_below
            assert event['value'] == bet_above + bet_below


def test_finish_pool_above_four_bets(
    create_pool_contract_with_four_bets,
    round_id,
    pool_threshold,
    pool_value_delta,
):
    _, pool, _, finish_time = create_pool_contract_with_four_bets

    feed = get_contract('eth_usd_price_feed')
    keeper_registry_address = get_contract('keeper_registry').address
    feed.updateRoundData(
        round_id,
        pool_threshold + pool_value_delta,
        finish_time,
        finish_time,
    )

    bet_above = pool.getBetAmountAbove()
    bet_below = pool.getBetAmountBelow()

    assert pool.canFinish()

    tx = pool.finish({'from': keeper_registry_address})
    assert len(tx.events['Transfer']) == 2

    bet_accounts_above = [get_account(1), get_account(3)]
    
    for event in tx.events:
        if event.name == 'Transfer':
            assert event['to'] in bet_accounts_above
            bet_amount = pool.getBetAmountAboveForAddress(event['to'])
            assert event['value'] == bet_amount + bet_below * float(bet_amount) / bet_above


def test_finish_pool_below_four_bets(
    create_pool_contract_with_four_bets,
    round_id,
    pool_threshold,
    pool_value_delta,
):
    _, pool, _, finish_time = create_pool_contract_with_four_bets

    feed = get_contract('eth_usd_price_feed')
    keeper_registry_address = get_contract('keeper_registry').address
    feed.updateRoundData(
        round_id,
        pool_threshold - pool_value_delta,
        finish_time,
        finish_time,
    )

    bet_above = pool.getBetAmountAbove()
    bet_below = pool.getBetAmountBelow()

    assert pool.canFinish()

    tx = pool.finish({'from': keeper_registry_address})
    assert len(tx.events['Transfer']) == 2

    bet_accounts_below = [get_account(2), get_account(4)]
    
    for event in tx.events:
        if event.name == 'Transfer':
            assert event['to'] in bet_accounts_below
            bet_amount = pool.getBetAmountBelowForAddress(event['to'])
            assert event['value'] == bet_amount + bet_above * float(bet_amount) / bet_below
