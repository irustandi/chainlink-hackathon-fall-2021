// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockKeeperRegistry {
    mapping (uint => uint96) upkeepBalance;
    uint96 totalBalance;
    address linkToken;

    event FundsAdded(uint256 indexed id, address indexed from, uint96 amount);

    constructor(address _linkToken) {
        linkToken = _linkToken;
    }

    function onTokenTransfer(
        address sender,
        uint amount,
        bytes calldata data
    ) external {
        require(msg.sender == linkToken, "only callable through LINK");
        require(data.length == 32, "data must be 32 bytes");
        uint id = abi.decode(data, (uint));

        upkeepBalance[id] += uint96(amount);
        totalBalance += uint96(amount);

        emit FundsAdded(id, sender, uint96(amount));
    }
}