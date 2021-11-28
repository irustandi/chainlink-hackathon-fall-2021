// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IOrcBetPool {
    function addBet(uint256 _betAmountAbove, uint256 _betAmountBelow) external;
    function canFinish() view external returns (bool);
    function finish() external;
    function getBetAmountAbove() view external returns (uint256);
    function getBetAmountBelow() view external returns (uint256);
    function getBetAmountAboveForAddress(address addr) view external returns (uint256);
    function getBetAmountBelowForAddress(address addr) view external returns (uint256);
    function active() view external returns (bool);
}