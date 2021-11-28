// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "./OrcBetPool.sol";

contract OrcBetManager is KeeperCompatibleInterface, Ownable {
    OrcBetPool[] public allPools;
    LinkTokenInterface internal linkToken;
    address internal keeperRegistry;
    uint public keeperId;
    bool public initialized;
    uint public feeBps;
    uint public minBet;
    mapping (address => mapping (int => mapping (uint => address))) public getPool;
    mapping (address => bool) public isSupportedFeed;

    event BetPoolCreated(
        address indexed feed,
        int indexed threshold,
        uint timestamp,
        address pool,
        uint
    );

    constructor(
        address _linkToken,
        uint _feeBps,
        uint _minBet
    ) {
        require(_feeBps <= 500, "fee cannot be more than five percent");
        require(_minBet >= 1000000000, "minimum bet has to be larger than or equal to 1 gwei LINK");
        linkToken = LinkTokenInterface(_linkToken);
        feeBps = _feeBps;
        minBet = _minBet;
        initialized = false;
    }

    function initialize(
        address _keeperRegistry,
        uint _keeperId
    ) external onlyOwner {
        keeperRegistry = _keeperRegistry;
        keeperId = _keeperId;
        initialized = true;
    }

    function addFeed(address _feed) external onlyOwner {
        require(_feed != address(0), "cannot use zero address for feed");

        isSupportedFeed[_feed] = true;
    }

    function removeFeed(address _feed) external onlyOwner {
        require(_feed != address(0), "cannot use zero address for feed");

        isSupportedFeed[_feed] = false;
    }

    function createBetPool(
        address _feed,
        int _threshold,
        uint _timestamp
    ) external {
        require(initialized, "manager is not initialized yet");
        require(isSupportedFeed[_feed], "passing unsupported feed");
        require(_timestamp > block.timestamp, "timestamp has to be in the future");
        require(getPool[_feed][_threshold][_timestamp] == address(0), "pool already exists");
        // check existing bet for threshold, timestamp

        OrcBetPool pool = new OrcBetPool();
        pool.initialize(
            AggregatorV3Interface(_feed),
            _threshold,
            _timestamp,
            address(linkToken),
            feeBps,
            minBet
        );

        getPool[_feed][_threshold][_timestamp] = address(pool);
        allPools.push(pool);
        emit BetPoolCreated(
            _feed,
            _threshold,
            _timestamp,
            address(pool),
            allPools.length
        );
    }

    function setFee(
        uint _feeBps
    ) external onlyOwner {
        feeBps = _feeBps;
    }

    function setMinBet(
        uint _minBet
    ) external onlyOwner {
        minBet = _minBet;
    }

    function addFundsToKeeper(
        uint amount
    ) external onlyOwner {
        require(
            linkToken.balanceOf(address(this)) >= amount, 
            "amount to send is greater than balance"
        );
        linkToken.transferAndCall(
            keeperRegistry, 
            amount,
            abi.encode(keeperId)
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

    function performUpkeep(
        bytes calldata performData
    ) external override {
        if (!initialized) {
            return;
        }

        OrcBetPool[] memory canFinishPools = abi.decode(performData, (OrcBetPool[]));

        uint idx = 0;
        uint numPools = canFinishPools.length;

        for (idx = 0; idx < numPools; idx++) {
            canFinishPools[idx].finish();
        }
    }
}
