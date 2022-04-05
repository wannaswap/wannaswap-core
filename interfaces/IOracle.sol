// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

interface IOracle {
    function latestAnswer() external view returns (uint256);
    function latestTimestamp() external view returns (uint256);
    function latestRound() external view returns (uint256);
}