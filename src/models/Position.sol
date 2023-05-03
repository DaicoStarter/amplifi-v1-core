// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.19;

struct Position {
    address originator;
    uint256 realDebt;
    uint256 nominalDebt;
    address[] fungibles;
    mapping(address => uint256) fungibleBalances;
    address[] nonFungibles;
    mapping(address => uint256[]) nonFungibleIds;
}
