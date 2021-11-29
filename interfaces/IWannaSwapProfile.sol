// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

interface IWannaSwapProfile {

    event SetIsStartRefCompetition(bool isStartRefCompetition);
    event SetEmissionAdder(address indexed user, bool isEmissionAdder);
    event SetVolumeUser(address indexed user, bool isVolumeUser);
    event SetReferrer(address indexed user, address indexed referrer);
    event SetLastSwap(address indexed user, uint volume);
    event AddTeam(address indexed user);
    event ChangeTeam(address indexed user, uint value);
    event AddEmission(address indexed user, uint value);
    event UseVolume(address indexed user, uint value);
    event UseRefVolume(address indexed user, uint value);

    function teamid(address _user) external view returns (uint);
    function referrer(address _user) external view returns (address);
    function setReferrer(address _user, address _referrer) external;
    function setLastSwap(address _user, uint _volume) external;
    function addTeam() external;
    function changeTeam(uint _tid) external;
    function addEmission(address _user, uint _amount) external;
    function useVolume(address _user, uint _vol) external;
    function useRefVolume(address _user, uint _vol) external;
}