// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IOrcBetPool.sol";

contract OrcBetPool is IOrcBetPool, Ownable {
    struct BetInfo {
        uint betAmountAbove;
        uint betAmountBelow;
    }

    AggregatorV3Interface public feed;
    uint public feeBps;
    uint public minBet;
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
        isActive = false;
    }

    function getBetAmountAbove() view external override returns (uint256) {
        return betAmountAbove;
    }

    function getBetAmountBelow() view external override returns (uint256) {
        return betAmountBelow;
    }

    function initialize(
        AggregatorV3Interface _feed,
        int _threshold,
        uint _endTimestamp,
        address _betToken,
        uint _feeBps,
        uint _minBet
    ) external onlyOwner {
        feed = _feed;
        threshold = _threshold;
        endTimestamp = _endTimestamp;
        betToken = _betToken;
        createdTimestamp = block.timestamp;
        feeBps = _feeBps;
        minBet = _minBet;
        isActive = block.timestamp < endTimestamp; // part of requirement
    }

    function _calculateFeeAndEffectiveBet(
        uint _betAmount,
        uint _feeBps
    ) pure internal returns (
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
    ) external override {
        require(isActive, "not active");
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

    function canFinish() view external override returns (bool) {
        return isActive && block.timestamp >= endTimestamp;
    }

    function finish() external override {
        require(isActive, "not active");

        (
            uint80 roundId,
            int answer,
            uint startedAt,
            uint timestamp,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        if (timestamp >= endTimestamp) {
            if (betAmountAbove == 0 || betAmountBelow == 0 || answer == threshold) {
                // return bet to everyone
                _payBettors(0, betAmountAbove, betAmountBelow);
            } else if (answer > threshold) {
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
                roundId,
                timestamp,
                answer
            );
        }
    }
}
