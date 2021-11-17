// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

interface IWannaSwapProfile {
    event AddTeam(address indexed user);
    event ChangeTeam(address indexed user, uint value);
    event AddEmission(address indexed user, uint value);
    event UseVolume(address indexed user, uint value);
    event UseRefVolume(address indexed user, uint value);

    function teamid(address _user) external view returns (uint);
    function referrer(address _user) external view returns (address);
    function setReferrer(address _user) external;
    function setLastSwap(address _user, uint _volume) external;
    function addTeam() external;
    function changeTeam(uint _tid) external;
    function addEmission(address _user, uint _amount) external;
    function useVolume(address _user, uint _vol) external;
    function useRefVolume(address _user, uint _vol) external;
}