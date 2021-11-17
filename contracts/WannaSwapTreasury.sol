// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IWannaSwapProfile.sol";
import "../interfaces/IWannaSwapTreasury.sol";
import "./WannaSwapToken.sol";

contract WannaSwapTreasury is Ownable, ReentrancyGuard, IWannaSwapTreasury {
    string public name = "WannaSwap Treasury";
    using SafeMath for uint;
    using SafeERC20 for WannaSwapToken;

    struct UserInfo {
        uint tid;
        uint volume;
        uint claimedReward;
    }

    struct TeamInfo {
        uint totalVolume;
        uint lastSwap;
        uint totalReward;
        uint wannaPerShare;
    }

    struct RoundInfo {
        uint startTime;
        uint closeTime;
        uint totalReward;
        bool isClose;
    }

    WannaSwapToken public wanna;
    address public profileAddress;
    address public routerAddress;
    uint public maxReward;
    uint public mintedReward;
    uint public rewardPerRound;
    uint public roundTime;
    uint public top1TeamPercent;
    uint public top2TeamPercent;
    uint public top3TeamPercent;

    RoundInfo[] public roundInfo;
    mapping(uint => mapping (address => UserInfo)) public userInfo;
    mapping(uint => mapping (uint => TeamInfo)) public teamInfo;
    mapping(address => uint) public lastClaimedRound;

    constructor(
        WannaSwapToken _wanna,
        uint _maxReward,
        uint _rewardPerRound,
        uint _roundTime,
        uint _top1TeamPercent,
        uint _top2TeamPercent,
        uint _top3TeamPercent
    ) public {
        wanna = _wanna;
        maxReward = _maxReward;
        rewardPerRound = _rewardPerRound;
        roundTime = _roundTime;
        top1TeamPercent = _top1TeamPercent;
        top2TeamPercent = _top2TeamPercent;
        top3TeamPercent = _top3TeamPercent;
    }

    modifier onlyProfile() {
        require(msg.sender == profileAddress, "MUST BE PROFILE");
        _;
    }

    modifier onlyRouter() {
        require(msg.sender == routerAddress, "MUST BE ROUTER");
        _;
    }

    function setProfile(address _profileAddress) external override onlyOwner {
        // able to change once to keep safety
        require(profileAddress == address(0), "PROFILE HAS BEEN CHANGED");
        profileAddress = _profileAddress;
    }

    function setRouter(address _routerAddress) external override onlyOwner {
        // able to change once to keep safety
        require(routerAddress == address(0), "ROUTER HAS BEEN CHANGED");
        routerAddress = _routerAddress;
    }

    function setRewardPerRound(uint _rewardPerRound) external override onlyOwner {
        rewardPerRound = _rewardPerRound;
    }

    function setTopTeamPercents(uint _top1TeamPercent, uint _top2TeamPercent, uint _top3TeamPercent) external onlyOwner {
        require(_top1TeamPercent.add(_top2TeamPercent).add(_top3TeamPercent) == 100e18, "setTopTeamPercents: BAD PERCENTS");
        top1TeamPercent = _top1TeamPercent;
        top2TeamPercent = _top2TeamPercent;
        top3TeamPercent = _top3TeamPercent;
    }

    function setRoundTime(uint _roundTime) external onlyOwner {
        roundTime = _roundTime;
    }

    function roundLength() public view returns (uint) {
        return roundInfo.length;
    }

    // add the first round
    function start() external onlyOwner {
        if (roundInfo.length == 0) addRound();
    }

    function addRound() internal {
        uint totalReward = rewardPerRound.add(mintedReward) <= maxReward ? rewardPerRound : maxReward.sub(mintedReward);
        roundInfo.push(RoundInfo({
            startTime: block.timestamp,
            closeTime: block.timestamp.add(roundTime),
            totalReward: totalReward,
            isClose: false
        }));
    }

    function compareTeamVolume(uint _rid) public view returns (uint top1, uint top2, uint top3) {
        uint[] memory tops = new uint[](4);
        tops[0] = 0;
        tops[1] = 1;
        tops[2] = 2;
        tops[3] = 3;
        for (uint i = 1; i < tops.length - 1; i++) { // team0 is exception
            for (uint j = i + 1; j < tops.length; j++) {
                if (teamInfo[_rid][i].totalVolume < teamInfo[_rid][j].totalVolume
                    || (
                        teamInfo[_rid][i].totalVolume == teamInfo[_rid][j].totalVolume
                        && teamInfo[_rid][i].lastSwap > teamInfo[_rid][j].lastSwap
                    )) {
                    uint tmp = tops[i];
                    tops[i] = tops[j];
                    tops[j] = tmp;
                }
            }
        }

        return (tops[1], tops[2], tops[3]);
    }

    function updateTeam(uint _rid, uint _tid, uint _totalReward) internal {
        TeamInfo storage team = teamInfo[_rid][_tid];
        team.totalReward = _totalReward;
        if (team.totalVolume > 0) {
            team.wannaPerShare = team.totalReward.div(team.totalVolume);
        }
    }

    function closeRound(uint _rid) internal {
        require(_rid < roundInfo.length, "BAD ROUND");
        (uint top1, uint top2, uint top3) = compareTeamVolume(_rid);
        uint totalReward = roundInfo[_rid].totalReward;
        uint top1Reward = totalReward.mul(top1TeamPercent).div(100e18);
        uint top2Reward = totalReward.mul(top2TeamPercent).div(100e18);
        uint top3Reward = totalReward.sub(top1Reward).sub(top2Reward);
        updateTeam(_rid, top1, top1Reward);
        updateTeam(_rid, top2, top2Reward);
        updateTeam(_rid, top3, top3Reward);
        wanna.mint(address(this), totalReward);
        mintedReward = mintedReward.add(totalReward);
        roundInfo[_rid].isClose = true;
    }

    function addVolume(address _user, uint _vol) external override onlyRouter {
        IWannaSwapProfile profile = IWannaSwapProfile(profileAddress);
        uint tid = profile.teamid(_user);

        if (roundInfo.length > 0) {
            uint rid = roundInfo.length.sub(1);
            if (block.timestamp >= roundInfo[rid].closeTime) {
                // close old round
                closeRound(rid);
                // add new round
                addRound();
                rid = roundInfo.length.sub(1);
            }
            
            UserInfo storage user = userInfo[rid][_user];
            user.volume = user.volume.add(_vol);
            if (tid > 0) {
                user.tid = tid;
                TeamInfo storage team = teamInfo[rid][tid];
                team.totalVolume = team.totalVolume.add(_vol);
                team.lastSwap = block.timestamp;
            }

            emit AddVolume(_user, _vol);
        }
            
        profile.setLastSwap(_user, _vol);
    }

    function pendingWanna(address _user) public view returns (uint) {
        uint result = 0;

        for (uint i = lastClaimedRound[_user]; i < roundInfo.length; i++) {
            RoundInfo storage round = roundInfo[i];
            if (round.isClose) {
                UserInfo storage user = userInfo[i][_user];
                if (user.volume > 0) {
                    uint tid = user.tid;
                    TeamInfo storage team = teamInfo[i][tid];
                    result = result.add(team.totalReward.mul(user.volume).div(team.totalVolume));
                    if (result >= user.claimedReward) {
                        result = result.sub(user.claimedReward);
                    }
                }
            }
        }

        return result;
    }

    function changeTeam(address _user, uint _tid) external override onlyProfile {
        if (roundInfo.length > 0) {
            uint rid = roundInfo.length.sub(1);
            if (block.timestamp >= roundInfo[rid].closeTime) {
                // close old round
                closeRound(rid);
                // add new round
                addRound();
                rid = roundInfo.length.sub(1);
            }
            UserInfo storage user = userInfo[rid][_user];
            uint tid = user.tid;
            TeamInfo storage team = teamInfo[rid][tid];
            if (team.totalVolume >= user.volume) {
                team.totalVolume = team.totalVolume.sub(user.volume);
            }

            user.tid = _tid;
            user.volume = 0;
        }
    }

    function claimReward() external override nonReentrant {
        // start from lastClaimedRound to save fee
        for (uint i = lastClaimedRound[msg.sender]; i < roundInfo.length; i++) {
            RoundInfo storage round = roundInfo[i];
            if (round.isClose) {
                UserInfo storage user = userInfo[i][msg.sender];
                if (user.volume > 0) {
                    uint tid = user.tid;
                    TeamInfo storage team = teamInfo[i][tid];
                    uint reward = team.totalReward.mul(user.volume).div(team.totalVolume);
                    if (reward >= user.claimedReward) {
                        reward = reward.sub(user.claimedReward);
                        uint balance = wanna.balanceOf(address(msg.sender));
                        if (reward > balance) {
                            reward = balance;
                        }
                        user.claimedReward = user.claimedReward.add(reward);
                        wanna.safeTransfer(address(msg.sender), reward);

                        emit ClaimReward(i, msg.sender, reward);
                    }
                }
                lastClaimedRound[msg.sender] = i;
            }
        }
    }

    receive() external payable {}
}