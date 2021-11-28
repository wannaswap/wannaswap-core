// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IRewarder.sol";
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
        address rewarder; // bonus other tokens, ex: AURORA
    }

    WannaSwapToken public immutable wanna;
    address public immutable profile;
    address public immutable burnAddress = address(0x000000000000000000000000000000000000dEaD);
    uint public immutable claimableTime = 1639396800; // Monday, December 13, 2021 12:00:00 PM
    uint public refPercent;
    bool public isEnableRef;

    uint public totalWanna;
    uint public mintedWanna;
    uint public wannaPerBlock; // actually per second to be more stable

    PoolInfo[] public poolInfo;
    mapping (address => uint) poolIndex;
    mapping (uint => mapping (address => UserInfo)) public userInfo;
    uint public totalAllocPoint;

    event SetEmissionRate(uint wannaPerBlock);
    event SetTotalWanna(uint totalWanna);
    event SetPercent(uint refPercent);
    event SetIsEnableRef(bool isEnableRef);
    event AddPool(uint allocPoint, address lpToken, address rewarder, bool withUpdate);
    event SetPool(uint indexed pid, uint allocPoint, address rewarder, bool withUpdate);
    event SetBonusEmissionRate(uint indexed pid, uint rewardPerBlock);
    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event EmergencyWithdraw(address indexed user, uint indexed pid, uint amount);

    constructor(
        WannaSwapToken _wanna,
        address _profile,
        uint _totalWanna,
        uint _wannaPerBlock,
        uint _refPercent
    ) public {
        wanna = _wanna;
        profile = _profile;
        totalWanna = _totalWanna;
        wannaPerBlock = _wannaPerBlock;
        refPercent = _refPercent;
    }

    function setEmissionRate(uint _wannaPerBlock) external onlyOwner {
        updateAllPools();
        wannaPerBlock = _wannaPerBlock;
        
        emit SetEmissionRate(_wannaPerBlock);
    }

    function setTotalWanna(
        uint _totalWanna) external onlyOwner {
        updateAllPools();
        require(_totalWanna <= wanna.maxSupply(), "setTotalWanna: BAD totalWanna");
        require(_totalWanna >= mintedWanna, "setTotalWanna: BAD totalWanna");
        totalWanna = _totalWanna;

        emit SetTotalWanna(_totalWanna);
    }

    function setPercent(
        uint _refPercent) external onlyOwner {
        require(_refPercent < 100e18, "setPercent: BAD PERCENT");
        updateAllPools();
        refPercent = _refPercent;

        emit SetPercent(_refPercent);
    }

    function setIsEnableRef(
        bool _isEnableRef) external onlyOwner {
        isEnableRef = _isEnableRef;

        emit SetIsEnableRef(_isEnableRef);
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    function addPool(uint _allocPoint, IERC20 _lpToken, address _rewarder, bool _withUpdate) external onlyOwner {
        // prevent from adding a pool twice
        require(poolIndex[address(_lpToken)] == 0, "addPool: EXISTED POOL");
        if (_withUpdate) {
            updateAllPools();
        }

        uint lastRewardBlock = block.timestamp;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accWannaPerShare: 0,
            totalLp: 0,
            rewarder: _rewarder
        }));
        poolIndex[address(_lpToken)] = poolInfo.length;

        emit AddPool(_allocPoint, address(_lpToken), _rewarder, _withUpdate);
    }

    function setPool(uint _pid, uint _allocPoint, address _rewarder, bool _withUpdate) external onlyOwner {
        require(_pid < poolInfo.length, "setPool: BAD POOL");
        if (_withUpdate) {
            updateAllPools();
        }
        totalAllocPoint = totalAllocPoint.add(_allocPoint).sub(poolInfo[_pid].allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].rewarder = _rewarder;

        emit SetPool(_pid, _allocPoint, _rewarder, _withUpdate);
    }

    function setBonusEmissionRate(uint _pid, uint _rewardPerBlock) external onlyOwner {
        require(_pid < poolInfo.length, "setBonusEmissionRate: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];

        updatePool(_pid);

        if (pool.rewarder != address(0)) {
            uint blockCount = getBlockCount(pool.lastRewardBlock, block.timestamp);
            uint lpSupply = pool.totalLp;
            IRewarder(pool.rewarder).setRewardPerBlock(_rewardPerBlock, blockCount, lpSupply);
        }

        emit SetBonusEmissionRate(_pid, _rewardPerBlock);
    }

    function getBlockCount(uint _from, uint _to) public view returns (uint) {
        return _to.sub(_from);
    }

    function pendingWanna(uint _pid, address _user) public view returns (uint) {
        require(_pid < poolInfo.length, "pendingWanna: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint accWannaPerShare = pool.accWannaPerShare;
        uint lpSupply = pool.totalLp;
        uint lastRewardBlock = pool.lastRewardBlock;
        if (block.timestamp > lastRewardBlock && lpSupply != 0) {
            uint blockCount = getBlockCount(lastRewardBlock, block.timestamp);
            uint wannaReward = blockCount.mul(wannaPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

            uint farmWanna = calculate(wannaReward);

            accWannaPerShare = accWannaPerShare.add(farmWanna.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accWannaPerShare).div(1e18).sub(user.rewardDebt).add(user.lockedReward);
    }

    function pendingBonus(uint _pid, address _user) public view returns (uint) {
        require(_pid < poolInfo.length, "pendingWanna: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        address rewarder = pool.rewarder;
        if (rewarder == address(0)) {
            return 0;
        }

        UserInfo storage user = userInfo[_pid][_user];
        uint lpSupply = pool.totalLp;
        uint lastRewardBlock = pool.lastRewardBlock;
        if (block.timestamp > lastRewardBlock && lpSupply != 0) {
            uint blockCount = getBlockCount(lastRewardBlock, block.timestamp);
            
            return IRewarder(rewarder).pendingReward(_user, user.amount, blockCount, lpSupply);
        }
        return 0;
    }

    function updateAllPools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    function calculate(uint _reward) public view returns (uint farmWanna) {
        uint curTotalWanna = totalWanna;
        uint curMintedWanna = mintedWanna;
        uint wannaMaxSupply = wanna.maxSupply();
        if (curTotalWanna > wannaMaxSupply) {
            curTotalWanna = wannaMaxSupply;
        }
        if (curTotalWanna <= curMintedWanna.add(_reward)) {
            _reward = curTotalWanna.sub(curMintedWanna);
        }
        
        farmWanna = _reward;
    }

    function updatePool(uint _pid) public {
        require(_pid < poolInfo.length, "updatePool: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        uint lastRewardBlock = pool.lastRewardBlock;
        if (block.timestamp <= lastRewardBlock) {
            return;
        }
        uint allocPoint = pool.allocPoint;
        uint lpSupply = pool.totalLp;
        if (lpSupply == 0 || allocPoint == 0) {
            pool.lastRewardBlock = block.timestamp;
            return;
        }

        uint blockCount = getBlockCount(lastRewardBlock, block.timestamp);
        uint wannaReward = blockCount.mul(wannaPerBlock).mul(allocPoint).div(totalAllocPoint);

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

            address profileAddress = profile;
            if (profileAddress != address(0) && isEnableRef) {
                uint refPending = pending.mul(refPercent).div(100e18); // referrer's reward = <refPercent> % referral's reward
                refPending = calculate(refPending);

                if (refPending > 0) {
                    mintedWanna = mintedWanna.add(refPending);
                    IWannaSwapProfile profileContract = IWannaSwapProfile(profileAddress);
                    address referrer = profileContract.referrer(_user);
                    if (referrer == address(0)) {
                        referrer = burnAddress; // if user does NOT have referrer => burn
                    }
                    profileContract.addEmission(_user, refPending);
                    wanna.mint(referrer, refPending);
                }
            }
            
            address rewarder = pool.rewarder;
            if (rewarder != address(0)) {
                uint blockCount = getBlockCount(pool.lastRewardBlock, block.timestamp);
                uint lpSupply = pool.totalLp;
                IRewarder(rewarder).onReward(_user, amount, blockCount, lpSupply);
            }

            user.rewardDebt = amount.mul(pool.accWannaPerShare).div(1e18);
        }
        user.lockedReward = 0; // after first harvest, lockred reward's always 0
    }

    function deposit(uint _pid, uint _amount, address _ref) external nonReentrant {
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

        address profileAddress = profile;
        if (profileAddress != address(0) && _ref != address(0)) {
            IWannaSwapProfile(profileAddress).setReferrer(_ref);
        }
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint _pid, uint _amount) external nonReentrant {
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

    function emergencyWithdraw(uint _pid) external {
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