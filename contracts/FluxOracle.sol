// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "../interfaces/IOracle.sol";

interface IFluxOracle {
    function latestAnswer() external view returns (uint256);
    function latestTimestamp() external view returns (uint256);
    function latestRound() external view returns (uint256);
}

contract FluxOracle is IOracle {
    IFluxOracle public immutable oracle;

    constructor(
        address _oracle
    ) public {
        oracle = IFluxOracle(_oracle);
    }

    function latestAnswer() external view override returns (uint256) {
        return oracle.latestAnswer();
    }

    function latestTimestamp() external view override returns (uint256) {
        return oracle.latestTimestamp();
    }

    function latestRound() external view override returns (uint256) {
        return oracle.latestRound();
    }
}