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

    WannaSwapToken public immutable wanna;
    address public immutable treasuryAddress;
    bool public isStartRefCompetition;

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

        emit SetIsStartRefCompetition(_isStartRefCompetition);
    }

    function setEmissionAdder(address _user, bool _isEmissionAdder) external onlyOwner {
        emissionAdder[_user] = _isEmissionAdder;

        emit SetEmissionAdder(_user, _isEmissionAdder);
    }

    function setVolumeUser(address _user, bool _isVolumeUser) external onlyOwner {
        volumeUser[_user] = _isVolumeUser;

        emit SetVolumeUser(_user, _isVolumeUser);
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

    function setReferrer(address _user, address _referrer) external override onlyEmissionAdder {
        if (_user != address(0)
            && _referrer != address(0)
            && _user != _referrer) {
            address curReferrer = userInfo[_user].referrer;
            if (curReferrer == address(0)) {
                userInfo[_user].referrer = _referrer;
                userInfo[_user].refTime = block.timestamp;
                ref[_referrer].push(_user);
                userInfo[_referrer].totalRef = userInfo[_referrer].totalRef.add(1);
            }

            emit SetReferrer(_user, _referrer);
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

        emit SetLastSwap(_user, _volume);
    }

    function changeTeam(uint _tid) external override {
        require(_tid > 0, "TEAM_ID MUST BE GREATER THAN 0");
        require(_tid < teamInfo.length, "BAD TEAM");
        uint curTid = userInfo[msg.sender].tid;
        if (curTid != _tid) {
            if (curTid != 0) { // not the first time
                // re-calculate userCount
                teamInfo[curTid].userCount = teamInfo[curTid].userCount.sub(1);
            }

            IWannaSwapTreasury treasury = IWannaSwapTreasury(treasuryAddress);
            treasury.changeTeam(address(msg.sender), _tid);
            teamInfo[_tid].userCount = teamInfo[_tid].userCount.add(1);
            userInfo[msg.sender].tid = _tid;

            emit ChangeTeam(msg.sender, _tid);
        }
    }

    function addEmission(address _user, uint _amount) external override onlyEmissionAdder {
        address curReferrer = userInfo[_user].referrer;
        if (curReferrer != address(0)) {
            userInfo[_user].emission = userInfo[_user].emission.add(_amount);
            userInfo[curReferrer].refEmission = userInfo[curReferrer].refEmission.add(_amount);

            emit AddEmission(_user, _amount);
        }
    }

    function useVolume(address _user, uint _vol) external override onlyVolumeUser {
        uint usedVolume = userInfo[_user].usedVolume;
        require(userInfo[_user].totalVolume >= usedVolume.add(_vol), "EXCEED TOTAL VOLUME");
        userInfo[_user].usedVolume = usedVolume.add(_vol);
        
        emit UseVolume(_user, _vol);
    }

    function useRefVolume(address _user, uint _vol) external override onlyVolumeUser {
        require(userInfo[_user].totalRefVolume >= userInfo[_user].usedRefVolume.add(_vol), "EXCEED TOTAL REF OLUME");
        userInfo[_user].usedRefVolume = userInfo[_user].usedRefVolume.add(_vol);
        
        emit UseRefVolume(_user, _vol);
    }

    receive() external payable {}
}