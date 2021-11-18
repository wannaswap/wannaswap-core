// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IWannaSwapProfile.sol";
import "./WannaSwapToken.sol";

contract WannaFarm is Ownable, ReentrancyGuard {
    string public name = "WannaFarm";
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    using SafeERC20 for WannaSwapToken;

    struct UserInfo {
        uint amount;
        uint rewardDebt;
        uint lockedReward; // can claim after <claimableTime>
    }

    struct PoolInfo {
        IERC20 lpToken;
        uint allocPoint;
        uint lastRewardBlock; // actually last timestamp to be more stable
        uint accWannaPerShare;
        uint totalLp;
    }

    WannaSwapToken public wanna;
    address public profile;
    uint public immutable startBlock; // actually start timestamp to be more stable
    address public immutable burnAddress = address(0x000000000000000000000000000000000000dEaD);
    uint public immutable claimableTime = 1638367200; // Wednesday, December 1, 2021 2:00:00 PM UTC
    uint public refPercent;
    bool public isEnableRef = false;

    uint public totalWanna;
    uint public mintedWanna;
    uint public wannaPerBlock; // actually per second to be more stable

    PoolInfo[] public poolInfo;
    mapping (address => uint) poolIndex;
    mapping (uint => mapping (address => UserInfo)) public userInfo;
    uint public totalAllocPoint = 0;

    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event EmergencyWithdraw(address indexed user, uint indexed pid, uint amount);

    constructor(
        WannaSwapToken _wanna,
        uint _totalWanna,
        uint _wannaPerBlock,
        uint _refPercent
    ) public {
        wanna = _wanna;
        totalWanna = _totalWanna;
        mintedWanna = 0;
        wannaPerBlock = _wannaPerBlock;
        refPercent = _refPercent;
        startBlock = block.timestamp;
    }

    function setProfile(address _profile) public onlyOwner {
        // able to change once to keep safety
        require(profile == address(0), "PROFILE HAS BEEN CHANGED");
        profile = _profile;
    }

    function setEmissionRate(uint _wannaPerBlock) public onlyOwner {
        updateAllPools();
        wannaPerBlock = _wannaPerBlock;
    }

    function setTotalWanna(
        uint _totalWanna) public onlyOwner {
        updateAllPools();
        require(_totalWanna >= mintedWanna, "setTotalWanna: BAD totalWanna");
        totalWanna = _totalWanna;
    }

    function setPercent(
        uint _refPercent) public onlyOwner {
        require(_refPercent < 100e18, "setPercent: BAD PERCENT");
        updateAllPools();
        refPercent = _refPercent;
    }

    function setIsEnableRef(
        bool _isEnableRef) public onlyOwner {
        isEnableRef = _isEnableRef;
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    function addPool(uint _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        // prevent from adding a pool twice
        require(poolIndex[address(_lpToken)] == 0, "addPool: EXISTED POOL");
        if (_withUpdate) {
            updateAllPools();
        }

        uint lastRewardBlock = block.timestamp > startBlock ? block.timestamp : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accWannaPerShare: 0,
            totalLp: 0
        }));
        poolIndex[address(_lpToken)] = poolInfo.length;
    }

    function setPool(uint _pid, uint _allocPoint, bool _withUpdate) public onlyOwner {
        require(_pid < poolInfo.length, "setPool: BAD POOL");
        if (_withUpdate) {
            updateAllPools();
        }
        totalAllocPoint = totalAllocPoint.add(_allocPoint).sub(poolInfo[_pid].allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function getBlockCount(uint _from, uint _to) public view returns (uint) {
        return _to.sub(_from);
    }

    function pendingWanna(uint _pid, address _user) public view returns (uint) {
        require(_pid < poolInfo.length, "pendingWanna: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint accWannaPerShare = pool.accWannaPerShare;
        uint lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardBlock && lpSupply != 0) {
            uint blockCount = getBlockCount(pool.lastRewardBlock, block.timestamp);
            uint wannaReward = blockCount.mul(wannaPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

            uint farmWanna = calculate(wannaReward);

            accWannaPerShare = accWannaPerShare.add(farmWanna.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accWannaPerShare).div(1e18).sub(user.rewardDebt).add(user.lockedReward);
    }

    function updateAllPools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    function calculate(uint _reward) public view returns (uint farmWanna) {
        if (totalWanna <= mintedWanna.add(_reward)) {
            _reward = totalWanna.sub(mintedWanna);
        }
        
        farmWanna = _reward;
    }

    function updatePool(uint _pid) public {
        require(_pid < poolInfo.length, "updatePool: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardBlock) {
            return;
        }
        uint lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.timestamp;
            return;
        }

        uint blockCount = getBlockCount(pool.lastRewardBlock, block.timestamp);
        uint wannaReward = blockCount.mul(wannaPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

        uint farmWanna = calculate(wannaReward);

        wanna.mint(address(this), farmWanna);
        mintedWanna = mintedWanna.add(farmWanna);

        pool.accWannaPerShare = pool.accWannaPerShare.add(farmWanna.mul(1e18).div(lpSupply));
        pool.lastRewardBlock = block.timestamp;
    }

    function harvest(uint _pid, address _user) internal {
        require(_pid < poolInfo.length, "harvest: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint amount = user.amount;
        if (amount > 0) {
            uint pending = pendingWanna(_pid, _user);
            uint balance = wanna.balanceOf(address(this));

            if (pending > balance) {
                pending = balance;
            }

            if (pending > 0) {
                wanna.transfer(_user, pending);
            }

            if (profile != address(0) && isEnableRef) {
                uint refPending = pending.mul(refPercent).div(100e18); // referrer's reward = <refPercent> % referral's reward
                if (mintedWanna.add(refPending) > totalWanna) {
                    refPending = totalWanna.sub(mintedWanna);
                }
                if (refPending > 0) {
                    mintedWanna = mintedWanna.add(refPending);
                    IWannaSwapProfile profileContract = IWannaSwapProfile(profile);
                    address referrer = profileContract.referrer(_user);
                    if (referrer == address(0)) {
                        referrer = burnAddress; // if user does NOT have referrer => burn
                    }
                    profileContract.addEmission(_user, refPending);
                    wanna.mint(referrer, refPending);
                }
            }

            user.rewardDebt = user.amount.mul(pool.accWannaPerShare).div(1e18);
        }
        user.lockedReward = 0; // after first harvest, lockred reward's always 0
    }

    function deposit(uint _pid, uint _amount) public nonReentrant {
        require(_pid < poolInfo.length, "deposit: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);
        if (block.timestamp >= claimableTime) {
            harvest(_pid, msg.sender);
        }
        else {
            user.lockedReward = pendingWanna(_pid, msg.sender);
        }

        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.totalLp = pool.totalLp.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accWannaPerShare).div(1e18);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint _pid, uint _amount) public nonReentrant {
        require(_pid < poolInfo.length, "withdraw: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: BAD AMOUNT");

        updatePool(_pid);
        if (block.timestamp >= claimableTime) {
            harvest(_pid, msg.sender);
        }
        else {
            user.lockedReward = pendingWanna(_pid, msg.sender);
        }

        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalLp = pool.totalLp.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accWannaPerShare).div(1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function emergencyWithdraw(uint _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint amount = user.amount;
        user.amount = 0;
        pool.totalLp = pool.totalLp.sub(amount);
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }
}