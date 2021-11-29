// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

interface IWannaSwapTreasury {
    event SetProfile(address indexed profileAddress);
    event SetRouter(address indexed routerAddress);
    event SetRewardPerRound(uint rewardPerRound);
    event SetTopTeamPercents(uint top1TeamPercent, uint top2TeamPercent, uint top3TeamPercent);
    event SetRoundTime(uint roundTime);
    event Start(address indexed user);
    event AddVolume(address indexed account, uint value);
    event ClaimReward(uint indexed bid, address indexed user, uint value);

    function setProfile(address _profileAddress) external;
    function setRouter(address _routerAddress) external;
    function setRewardPerRound(uint _rewardPerRound) external;
    function addVolume(address _account, uint _vol) external;
    function changeTeam(address _user, uint _tid) external;
    function claimReward() external;
}