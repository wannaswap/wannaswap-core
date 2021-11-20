// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IERC20Ext is IERC20 {
    function decimals() external returns (uint);
}

// Stake WANNAx to earn many other tokens
contract WannaStake is Ownable, ReentrancyGuard {
    string public name = "WannaStake";
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint amount;
        uint rewardDebt;
    }

    struct PoolInfo {
        IERC20 rewardToken;
        uint rewardPerBlock;   // actually per second
        uint tokenPrecision;
        uint wannaxStakedAmount;
        uint lastRewardBlock;  // actutally last reward timestamp
        uint accRewardPerShare;
        uint endTime;
        uint startTime;
        address protocolOwner;
    }

    IERC20 public immutable wannax;
    PoolInfo[] public poolInfo;
    mapping (address => uint) poolIndex;
    mapping (uint => mapping (address => UserInfo)) public userInfo;

    event RecoverWrongTokens(address tokenRecovered, uint amount);
    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event EmergencyWithdraw(address indexed user, uint indexed pid, uint amount);
    event SetRewardPerBlock(uint _pid, uint _gemsPerSecond);

    constructor(IERC20 _wannax) public {
        wannax = _wannax;
    }

    function stopReward(uint _pid) external onlyOwner {
        poolInfo[_pid].endTime = block.timestamp;
    }

    function recoverWrongTokens(address _token) external onlyOwner {
        require(_token != address(wannax), "recoverWrongTokens: Cannot be WANNAx");
        // prevent from adding a pool twice
        require(poolIndex[_token] == 0, "recoverWrongTokens: Existed pool");
        
        uint balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(address(msg.sender), balance);

        emit RecoverWrongTokens(_token, balance);
    }

    function emergencyRewardWithdraw(uint _pid, uint _amount) external onlyOwner {
        poolInfo[_pid].rewardToken.safeTransfer(poolInfo[_pid].protocolOwner, _amount);
    }

    function addPool(address _token, uint _rewardPerBlock, uint _startTime, uint _endTime, address _protocolOwner, bool _withUpdate) external onlyOwner {
        // prevent from adding a pool twice
        require(poolIndex[_token] == 0, "addPool: Existed pool");
        if (_withUpdate) {
            updateAllPools();
        }

        uint lastRewardBlock = block.timestamp > _startTime ? block.timestamp : _startTime;
        uint decimalsRewardToken = IERC20Ext(_token).decimals();
        require(decimalsRewardToken < 30, "addPool: Token has way too many decimals");
        uint precision = 10 ** (30 - decimalsRewardToken);

        poolInfo.push(PoolInfo({
            rewardToken: IERC20(_token),
            rewardPerBlock: _rewardPerBlock,
            tokenPrecision: precision,
            wannaxStakedAmount: 0,
            startTime: _startTime,
            endTime: _endTime,
            lastRewardBlock: lastRewardBlock,
            accRewardPerShare: 0,
            protocolOwner: _protocolOwner
        }));
    }

    function setPool(uint _pid, uint _rewardPerBlock, uint _startTime, uint _endTime, address _protocolOwner, bool _withUpdate) external onlyOwner {
        require(_pid < poolInfo.length, "setPool: This pool does not exist");
        if (_withUpdate) {
            updateAllPools();
        }

        poolInfo[_pid].rewardPerBlock = _rewardPerBlock;
        poolInfo[_pid].startTime = _startTime;
        poolInfo[_pid].endTime = _endTime;
        poolInfo[_pid].protocolOwner = _protocolOwner;
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    function getBlockCount(uint _from, uint _to, PoolInfo memory pool) internal view returns (uint) {
        _from = _from > pool.startTime ? _from : pool.startTime;
        if (_from > pool.endTime || _to < pool.startTime) {
            return 0;
        }
        if (_to > pool.endTime) {
            return pool.endTime.sub(_from);
        }
        return _to.sub(_from);
    }

    function pendingReward(uint _pid, address _user) external view returns (uint) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint accRewardPerShare = pool.accRewardPerShare;
        
        if (block.timestamp > pool.lastRewardBlock && pool.wannaxStakedAmount != 0) {
            uint blockCount = getBlockCount(pool.lastRewardBlock, block.timestamp, pool);
            uint reward = blockCount.mul(pool.rewardPerBlock);
            accRewardPerShare = accRewardPerShare.add(reward.mul(pool.tokenPrecision).div(pool.wannaxStakedAmount));
        }
        return user.amount.mul(accRewardPerShare).div(pool.tokenPrecision).sub(user.rewardDebt);
    }

    function updateAllPools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    function updatePool(uint _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardBlock) {
            return;
        }

        if (pool.wannaxStakedAmount == 0) {
            pool.lastRewardBlock = block.timestamp;
            return;
        }
        uint blockCount = getBlockCount(pool.lastRewardBlock, block.timestamp, pool);
        uint reward = blockCount.mul(pool.rewardPerBlock);

        pool.accRewardPerShare = pool.accRewardPerShare.add(reward.mul(pool.tokenPrecision).div(pool.wannaxStakedAmount));
        pool.lastRewardBlock = block.timestamp;
    }

    function deposit(uint _pid, uint _amount) external nonReentrant {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        uint pending = user.amount.mul(pool.accRewardPerShare).div(pool.tokenPrecision).sub(user.rewardDebt);

        user.amount = user.amount.add(_amount);
        pool.wannaxStakedAmount = pool.wannaxStakedAmount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(pool.tokenPrecision);

        if(pending > 0) {
            pool.rewardToken.safeTransfer(address(msg.sender), pending);
        }
        wannax.safeTransferFrom(address(msg.sender), address(this), _amount);

        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint _pid, uint _amount) external nonReentrant {  
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);

        uint pending = user.amount.mul(pool.accRewardPerShare).div(pool.tokenPrecision).sub(user.rewardDebt);

        user.amount = user.amount.sub(_amount);
        pool.wannaxStakedAmount = pool.wannaxStakedAmount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(pool.tokenPrecision);

        if(pending > 0) {
            pool.rewardToken.safeTransfer(address(msg.sender), pending);
        }

        wannax.safeTransfer(address(msg.sender), _amount);
        
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function emergencyWithdraw(uint _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint amount = user.amount;
        pool.wannaxStakedAmount = pool.wannaxStakedAmount.sub(user.amount);
        user.amount = 0;
        user.rewardDebt = 0;

        wannax.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);

    }

}