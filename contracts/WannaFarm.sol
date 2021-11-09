// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./WannaSwapToken.sol";

contract WannaFarm is Ownable, ReentrancyGuard {
    string public name = "WannaFarm";
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    using SafeERC20 for WannaSwapToken;

    struct UserInfo {
        uint amount;
        uint rewardDebt;
    }

    struct PoolInfo {
        IERC20 lpToken;
        uint allocPoint;
        uint lastRewardBlock; // last timestamp
        uint accWannaPerShare;
        uint totalLp;
    }

    WannaSwapToken public wanna;
    uint public startBlock; // start timestamp
    address public burnAddress = address(0x000000000000000000000000000000000000dEaD);
    uint public burnPercent;

    uint public totalWanna;
    uint public mintedWanna;
    uint public wannaPerBlock; // per second

    PoolInfo[] public poolInfo;
    mapping (uint => mapping (address => UserInfo)) public userInfo;
    uint public totalAllocPoint = 0;

    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event EmergencyWithdraw(address indexed user, uint indexed pid, uint amount);

    constructor(
        WannaSwapToken _wanna,
        uint _totalWanna,
        uint _wannaPerBlock,
        uint _burnPercent
    ) public {
        wanna = _wanna;
        totalWanna = _totalWanna;
        mintedWanna = 0;
        wannaPerBlock = _wannaPerBlock;
        burnPercent = _burnPercent;
        startBlock = block.timestamp;
    }

    function setEmissionRate(uint _wannaPerBlock) public onlyOwner {
        updateAllPools();
        wannaPerBlock = _wannaPerBlock;
    }

    function setTotalWanna(
        uint _totalWanna) public onlyOwner {
        updateAllPools();
        require(_totalWanna >= mintedWanna, "setTotalWanna: BAD TOTALWANNA");
        totalWanna = _totalWanna;
    }

    function setPercent(
        uint _burnPercent) public onlyOwner {
        require(_burnPercent < 100e18, "setPercent: BAD PERCENT");
        updateAllPools();
        burnPercent = _burnPercent;
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    function addPool(uint _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
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

            ( , uint farmWanna) = calculate(wannaReward);

            accWannaPerShare = accWannaPerShare.add(farmWanna.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accWannaPerShare).div(1e18).sub(user.rewardDebt);
    }

    function updateAllPools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    function calculate(uint _reward) public view returns (uint burnWanna, uint farmWanna) {
        if (totalWanna <= mintedWanna.add(_reward)) {
            _reward = totalWanna.sub(mintedWanna);
        }
        
        burnWanna = _reward.mul(burnPercent).div(100e18);
        farmWanna = _reward.sub(burnWanna);
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

        (uint burnWanna, uint farmWanna) = calculate(wannaReward);

        wanna.mint(address(this), burnWanna.add(farmWanna));
        mintedWanna = mintedWanna.add(burnWanna).add(farmWanna);
        if (burnWanna > 0) {
            wanna.transfer(burnAddress, burnWanna);
        }

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

            if(pending > 0) {
                wanna.transfer(_user, pending);
            }

            user.rewardDebt = user.amount.mul(pool.accWannaPerShare).div(1e18);
        }
    }

    function deposit(uint _pid, uint _amount) public nonReentrant {
        require(_pid < poolInfo.length, "deposit: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);
        harvest(_pid, msg.sender);

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
        harvest(_pid, msg.sender);

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