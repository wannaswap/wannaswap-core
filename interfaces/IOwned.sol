// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

interface IOwned {
    // this function isn't abstract since the compiler emits automatically generated getter functions as external
    function transferOwnership(address _newOwner) external;
    function acceptOwnership() external;
}