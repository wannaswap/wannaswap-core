// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IWannaSwapProfile.sol";
import "../interfaces/IWannaSwapTreasury.sol";
import "./WannaSwapToken.sol";

contract WannaSwapProfile is Ownable, IWannaSwapProfile {
    string public name = "WannaSwap Profile";
    using SafeMath for uint;
    using SafeERC20 for WannaSwapToken;

    struct UserInfo {
        uint tid;
        address referrer;
        uint refTime;
        uint lastSwap;
        uint lastSwapVolume;
        uint totalVolume;
        uint usedVolume;
        uint totalRef;
        uint totalRefVolume;
        uint usedRefVolume;
        uint emission;
        uint refEmission;
    }

    struct TeamInfo {
        uint userCount;
    }

    WannaSwapToken public wanna;
    address public treasuryAddress;
    bool public isStartRefCompetition = false;

    TeamInfo[] public teamInfo;
    mapping(address => UserInfo) public userInfo;
    mapping(address => address[]) public ref;
    mapping(address => bool) public volumeUser;
    mapping(address => bool) public emissionAdder;

    constructor(
        WannaSwapToken _wanna,
        address _treasuryAddress
    ) public {
        wanna = _wanna;
        treasuryAddress = _treasuryAddress;
    }

    modifier onlyEmissionAdder() {
        require(emissionAdder[msg.sender], "MUST BE EMISSION ADDER");
        _;
    }

    modifier onlyVolumeUser() {
        require(volumeUser[msg.sender], "MUST BE VOLUME USER");
        _;
    }

    modifier onlyTreasury() {
        require(msg.sender == treasuryAddress, "MUST BE TREASURY");
        _;
    }

    function setIsStartRefCompetition(bool _isStartRefCompetition) external onlyOwner {
        isStartRefCompetition = _isStartRefCompetition;
    }

    function setEmissionAdder(address _user, bool _isEmissionAdder) public onlyOwner {
        emissionAdder[_user] = _isEmissionAdder;
    }

    function setVolumeUser(address _user, bool _isVolumeUser) public onlyOwner {
        volumeUser[_user] = _isVolumeUser;
    }

    function teamid(address _user) external override view returns (uint) {
        return userInfo[_user].tid;
    }

    function referrer(address _user) external override view returns (address) {
        return userInfo[_user].referrer;
    }

    function teamLength() external view returns (uint) {
        return teamInfo.length > 0 ? teamInfo.length.sub(1) : 0; // team0 is exception
    }

    function setReferrer(address _user) external override {
        require(_user != address(0), "INVALID USER");
        require(_user != msg.sender, "INVALID USER");
        if (userInfo[msg.sender].referrer == address(0)) {
            userInfo[msg.sender].referrer = _user;
            userInfo[msg.sender].refTime = block.timestamp;
            ref[_user].push(msg.sender);
            userInfo[_user].totalRef = userInfo[_user].totalRef.add(1);
        }
    }

    function addTeam() external override onlyOwner {
        teamInfo.push(TeamInfo(
            {
                userCount: 0
            }
        ));

        emit AddTeam(msg.sender);
    }

    function setLastSwap(address _user, uint _volume) external override onlyTreasury {
        userInfo[_user].lastSwap = block.timestamp;
        userInfo[_user].lastSwapVolume = _volume;
        userInfo[_user].totalVolume = userInfo[_user].totalVolume.add(_volume);
        if (isStartRefCompetition && userInfo[_user].referrer != address(0)) {
            address userReferrer = userInfo[_user].referrer;
            userInfo[userReferrer].totalRefVolume = userInfo[userReferrer].totalRefVolume.add(_volume);
        }
    }

    function changeTeam(uint _tid) external override {
        require(_tid > 0, "TEAM_ID MUST BE GREATER THAN 0");
        require(_tid < teamInfo.length, "BAD TEAM");
        uint currentTid = userInfo[msg.sender].tid;
        if (currentTid != _tid) {
            if (currentTid != 0) { // not the first time
                // re-calculate userCount
                teamInfo[currentTid].userCount = teamInfo[currentTid].userCount.sub(1);
            }

            IWannaSwapTreasury treasury = IWannaSwapTreasury(treasuryAddress);
            treasury.changeTeam(address(msg.sender), _tid);
            teamInfo[_tid].userCount = teamInfo[_tid].userCount.add(1);
            userInfo[msg.sender].tid = _tid;

            emit ChangeTeam(msg.sender, _tid);
        }
    }

    function addEmission(address _user, uint _amount) external override onlyEmissionAdder {
        if (userInfo[_user].referrer != address(0)) {
            userInfo[_user].emission = userInfo[_user].emission.add(_amount);
            userInfo[userInfo[_user].referrer].refEmission = userInfo[userInfo[_user].referrer].refEmission.add(_amount);

            emit AddEmission(_user, _amount);
        }
    }

    function useVolume(address _user, uint _vol) external override onlyVolumeUser {
        require(userInfo[_user].totalVolume >= userInfo[_user].usedVolume.add(_vol), "EXCEED TOTAL VOLUME");
        userInfo[_user].usedVolume = userInfo[_user].usedVolume.add(_vol);
        
        emit UseVolume(_user, _vol);
    }

    function useRefVolume(address _user, uint _vol) external override onlyVolumeUser {
        require(userInfo[_user].totalRefVolume >= userInfo[_user].usedRefVolume.add(_vol), "EXCEED TOTAL REF OLUME");
        userInfo[_user].usedRefVolume = userInfo[_user].usedRefVolume.add(_vol);
        
        emit UseRefVolume(_user, _vol);
    }

    receive() external payable {}
}