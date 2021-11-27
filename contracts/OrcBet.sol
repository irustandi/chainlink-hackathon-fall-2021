// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/Denominations.sol";

contract OrcBetManager is KeeperCompatibleInterface, Ownable {
    OrcBetPool[] public allPools;
    FeedRegistryInterface internal registry;
    LinkTokenInterface internal linkToken;
    address internal keeperRegistry;
    uint public keeperId;
    bool public initialized;
    mapping (address => mapping (address => mapping (int => mapping (uint => address)))) public getPool;

    event BetPoolCreated(
        address indexed base,
        address indexed quote,
        int indexed threshold,
        uint timestamp,
        address pool,
        uint
    );

    constructor() {
        initialized = false;
    }

    function initialize(
        address _registry,
        address _keeperRegistry,
        uint _keeperId,
        address _linkToken
    ) external onlyOwner {
        registry = FeedRegistryInterface(_registry);
        keeperRegistry = _keeperRegistry;
        keeperId = _keeperId;
        linkToken = LinkTokenInterface(_linkToken);
        initialized = true;
    }

    function createBetPool(
        address _base,
        address _quote,
        int _threshold,
        uint _timestamp
    ) external {
        require(initialized);
        require(_timestamp > block.timestamp, "timestamp has to be in the future");
        require(getPool[_base][_quote][_threshold][_timestamp] == address(0), "pool already exists");
        // check existing bet for base, quote, threshold, timestamp

        // check availability of feed
        AggregatorV3Interface feed = registry.getFeed(_base, _quote);

        OrcBetPool pool = new OrcBetPool();
        pool.initialize(
            _base,
            _quote,
            _threshold,
            _timestamp,
            address(linkToken)
        );

        getPool[_base][_quote][_threshold][_timestamp] = address(pool);
        allPools.push(pool);
        emit BetPoolCreated(
            _base,
            _quote,
            _threshold,
            _timestamp,
            address(pool),
            allPools.length
        );
    }

    function checkUpkeep(
        bytes calldata checkData
    ) external override returns (
        bool upkeepNeeded,
        bytes memory performData
    ) {
        if (initialized) {
            upkeepNeeded = false;
            uint numPools = allPools.length;
            uint[] memory canFinishIdxs = new uint[](numPools);
            uint numCanFinishPools = 0;

            for (uint idx = 0; idx < numPools; idx++) {
                bool canFinish = allPools[idx].canFinish();

                if (canFinish) {
                    upkeepNeeded = true;
                    canFinishIdxs[numCanFinishPools] = idx;
                    numCanFinishPools++;
                }
            }

            if (upkeepNeeded) {
                OrcBetPool[] memory canFinishPools = new OrcBetPool[](numCanFinishPools);
                for (uint idx = 0; idx < numCanFinishPools; idx++) {
                    canFinishPools[idx] = allPools[canFinishIdxs[idx]];
                }
                performData = abi.encode(canFinishPools);
            }
        }
    }

    // TODO: cleanup non-active pool
    function performUpkeep(
        bytes calldata performData
    ) external override {
        if (!initialized) {
            return;
        }

        // send LINK balance to keeper
        if (linkToken.balanceOf(address(this)) > 0) {
            linkToken.transferAndCall(
                keeperRegistry, 
                linkToken.balanceOf(address(this)),
                abi.encode(keeperId)
            );
        }

        OrcBetPool[] memory canFinishPools = abi.decode(performData, (OrcBetPool[]));

        uint idx = 0;
        uint numPools = canFinishPools.length;

        for (idx = 0; idx < numPools; idx++) {
            canFinishPools[idx].finish(registry);
        }
    }
}

contract OrcBetPool is Ownable {
    struct BetInfo {
        uint betAmountAbove;
        uint betAmountBelow;
    }

    uint public feeBps;
    uint public minBet;
    address public base;
    address public quote;
    bool public isActive;
    uint public createdTimestamp;
    uint public endTimestamp;
    int public threshold;
    address public betToken;
    uint public betAmountAbove;
    uint public betAmountBelow;
    address[] public bettors;
    mapping(address => BetInfo) betInfoMap;

    event Bet(
        address indexed sender,
        uint betAmountAbove,
        uint feeAbove,
        uint betAmountBelow,
        uint feeBelow
    );
    event FinishPool(
        uint poolTimestamp,
        int threshold,
        uint80 roundId,
        uint feedTimestamp,
        int value
    );

    constructor() {
        isActive = block.timestamp < endTimestamp; // part of requirement
    }

    function initialize(
        address _base,
        address _quote,
        int _threshold,
        uint _endTimestamp,
        address _betToken
    ) external onlyOwner {
        // check the inputs
        base = _base;
        quote = _quote;
        threshold = _threshold;
        endTimestamp = _endTimestamp;
        betToken = _betToken;
        createdTimestamp = block.timestamp;
    }

    function _calculateFeeAndEffectiveBet(
        uint _betAmount,
        uint _feeBps
    ) internal returns (
        uint effectiveBet,
        uint fee
    ) {
        fee = _betAmount > 0 ? _betAmount * _feeBps / 10000 : 0;
        effectiveBet = _betAmount > 0 ? _betAmount - fee : 0;
    }

    function _updateBet(
        address _sender,
        uint _betAbove,
        uint _betBelow
    ) internal {
        BetInfo storage betInfo = betInfoMap[_sender];
        bool existing = betInfo.betAmountAbove > 0 || betInfo.betAmountBelow > 0;
        if (_betAbove > 0) {
            betInfo.betAmountAbove += _betAbove;
        }
        if (_betBelow > 0) {
            betInfo.betAmountBelow += _betBelow;
        }

        if (!existing) {
            bettors.push(_sender);
        }
    }

    function _getFinalAnswer(
        FeedRegistryInterface _registry,
        address _base,
        address _quote,
        uint80 _latestRoundId,
        int _latestAnswer,
        uint _latestTimestamp,
        uint _refTimestamp
    ) internal returns (
        uint80 finalRoundId, 
        uint finalTimestamp, 
        int finalAnswer
    ) {
        uint80 roundId = _latestRoundId;
        uint timestamp = _latestTimestamp;
        finalRoundId = _latestRoundId;
        finalTimestamp = _latestTimestamp;
        finalAnswer = _latestAnswer;

        while (timestamp >= _refTimestamp) {
            roundId = _registry.getPreviousRoundId(_base, _quote, roundId);
            int answer;
            uint startedAt;
            uint80 answeredInRound;

            {
                (
                    roundId,
                    answer,
                    startedAt,
                    timestamp,
                    answeredInRound
                ) = _registry.getRoundData(_base, _quote, roundId);
            }

            if (timestamp >= _refTimestamp) {
                finalRoundId = roundId;
                finalTimestamp = timestamp;
                finalAnswer = answer;
            }
        }
    }

    function _payBettors(
        int side,
        uint betTotalAbove,
        uint betTotalBelow
    ) internal {
        uint numBettors = bettors.length;

        if (side == 0) {
            // pay everybody their total effective bet
            for (uint idx = 0; idx < numBettors; idx++) {
                BetInfo storage betInfo = betInfoMap[bettors[idx]];
                uint transferAmount = betInfo.betAmountAbove + betInfo.betAmountBelow;
                if (transferAmount > 0) {
                    IERC20(betToken).transfer(bettors[idx], transferAmount);
                }
            }
        } else if (side > 0) {
            // pay everybody their above effective bet
            for (uint idx = 0; idx < numBettors; idx++) {
                BetInfo storage betInfo = betInfoMap[bettors[idx]];
                if (betInfo.betAmountAbove > 0) {
                    uint transferAmount = betInfo.betAmountAbove + betTotalBelow * betInfo.betAmountAbove / betTotalAbove ;
                    if (transferAmount > 0) {
                        IERC20(betToken).transfer(bettors[idx], transferAmount);
                    }
                }
            }
        } else {
            // pay everybody their below effective bet
            for (uint idx = 0; idx < numBettors; idx++) {
                BetInfo storage betInfo = betInfoMap[bettors[idx]];
                if (betInfo.betAmountBelow > 0) {
                    uint transferAmount = betInfo.betAmountBelow + betTotalAbove * betInfo.betAmountBelow / betTotalBelow ;
                    if (transferAmount > 0) {
                        IERC20(betToken).transfer(bettors[idx], transferAmount);
                    }
                }
            }
        }

        // send leftover to pool manager
        uint balance = IERC20(betToken).balanceOf(address(this));
        if (balance > 0) {
            IERC20(betToken).transfer(owner(), balance);
        }
    }

    function addBet(
        uint256 _betAmountAbove,
        uint256 _betAmountBelow
    ) external {
        require(_betAmountAbove + _betAmountBelow >= minBet, "bet amount below minimum");
        require(IERC20(betToken).balanceOf(msg.sender) >= _betAmountAbove + _betAmountBelow, "insufficient balance");

        // transfer bet from sender, sender needs to approve prior to this, should revert if this fails
        IERC20(betToken).transferFrom(msg.sender, address(this), _betAmountAbove + _betAmountBelow);

        (
            uint effectiveBetAbove,
            uint feeAbove
        ) = _calculateFeeAndEffectiveBet(_betAmountAbove, feeBps);
        (
            uint effectiveBetBelow,
            uint feeBelow
        ) = _calculateFeeAndEffectiveBet(_betAmountBelow, feeBps);

        uint totalFee = feeAbove + feeBelow;

        // transfer fee to contract owner
        IERC20(betToken).transfer(owner(), totalFee);

        _updateBet(msg.sender, effectiveBetAbove, effectiveBetBelow);

        betAmountAbove += effectiveBetAbove;
        betAmountBelow += effectiveBetBelow;

        // emit event
        emit Bet(msg.sender, effectiveBetAbove, feeAbove, effectiveBetBelow, feeBelow);
    }

    function canFinish() view external returns (bool) {
        return isActive && block.timestamp >= endTimestamp;
    }

    function finish(
        FeedRegistryInterface registry
    ) external {
        require(isActive);

        (
            uint80 roundId,
            int answer,
            uint startedAt,
            uint timestamp,
            uint80 answeredInRound
        ) = registry.latestRoundData(base, quote);

        if (timestamp >= endTimestamp) {
            (
                uint80 finalRoundId,
                uint finalTimestamp,
                int finalAnswer
            ) = _getFinalAnswer(
                registry,
                base,
                quote,
                roundId,
                answer,
                timestamp,
                endTimestamp
            );

            if (betAmountAbove == 0 || betAmountBelow == 0 || finalAnswer == threshold) {
                // return bet to everyone
                _payBettors(0, betAmountAbove, betAmountBelow);
            } else if (finalAnswer > threshold) {
                // pay the bettorsAbove
                _payBettors(1, betAmountAbove, betAmountBelow);
            } else {
                // pay the bettorsBelow
                _payBettors(-1, betAmountAbove, betAmountBelow);
            }
            isActive = false;

            // emit event
            emit FinishPool(
                endTimestamp,
                threshold,
                finalRoundId,
                finalTimestamp,
                finalAnswer
            );
        }
    }
}
