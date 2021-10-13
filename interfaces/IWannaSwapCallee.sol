// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

interface IWannaSwapCallee {
    function wannaswapCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}