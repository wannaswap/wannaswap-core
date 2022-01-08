// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/IRewarder.sol";

contract Rewarder is IRewarder, Ownable {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardToken;
    IERC20 public immutable lpToken;
    address public immutable farm;

    // info of each WannaFarm user.
    struct UserInfo {
        uint amount;
        uint rewardDebt;
    }

    // info of each WannaFarm poolInfo.
    struct PoolInfo {
        uint accTokenPerShare;
        uint lastRewardBlock;
    }

    // info of the poolInfo.
    PoolInfo public poolInfo;
    // info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    uint public rewardPerBlock;
    uint private constant ACC_TOKEN_PRECISION = 1e18;

    event OnReward(address indexed user, uint amount);
    event SetRewardPerBlock(uint oldRate, uint newRate);

    modifier onlyWannaFarm() {
        require(msg.sender == farm, "onlyWannaFarm: only WannaFarm can call this function");
        _;
    }

    constructor(
        IERC20 _rewardToken,
        IERC20 _lpToken,
        uint _rewardPerBlock,
        address _farm
    ) public {
        rewardToken = _rewardToken;
        lpToken = _lpToken;
        rewardPerBlock = _rewardPerBlock;
        farm = _farm;
        poolInfo = PoolInfo({lastRewardBlock: block.timestamp, accTokenPerShare: 0});
    }
    
    // Unused params are required because of old WannaFarm contract
    function setRewardPerBlock(uint _rewardPerBlock, uint _blockCount, uint _lpSupply) external override onlyOwner {
        updatePool();

        uint oldRate = rewardPerBlock;
        rewardPerBlock = _rewardPerBlock;

        emit SetRewardPerBlock(oldRate, _rewardPerBlock);
    }

    function reclaimTokens(address token, uint amount, address payable to) public onlyOwner {
        if (token == address(0)) {
            to.transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function updatePool() public returns (PoolInfo memory pool) {
        pool = poolInfo;

        if (block.timestamp > pool.lastRewardBlock) {
            uint lpSupply = lpToken.balanceOf(address(farm));

            if (lpSupply > 0) {
                uint multiplier = block.timestamp.sub(pool.lastRewardBlock);
                uint tokenReward = multiplier.mul(rewardPerBlock);
                pool.accTokenPerShare = pool.accTokenPerShare.add((tokenReward.mul(ACC_TOKEN_PRECISION).div(lpSupply)));
            }

            pool.lastRewardBlock = block.timestamp;
            poolInfo = pool;
        }
    }

    // Unused params are required because of old WannaFarm contract 
    function onReward(address _user, uint _amount, uint _blockCount, uint _lpSupply) external override onlyWannaFarm {
        updatePool();
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        uint pendingBal;

        if (user.amount > 0) {
            pendingBal = (user.amount.mul(pool.accTokenPerShare).div(ACC_TOKEN_PRECISION)).sub(user.rewardDebt);
            uint rewardBal = rewardToken.balanceOf(address(this));
            if (pendingBal > rewardBal) {
                rewardToken.safeTransfer(_user, rewardBal);
            } else {
                rewardToken.safeTransfer(_user, pendingBal);
            }
        }

        user.amount = _amount;
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(ACC_TOKEN_PRECISION);

        emit OnReward(_user, pendingBal);
    }

    // Unused params are required because of old WannaFarm contract
    function pendingReward(address _user, uint _amount, uint _blockCount, uint _lpSupply) external view override returns (uint) {
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];

        uint accTokenPerShare = pool.accTokenPerShare;
        uint lpSupply = lpToken.balanceOf(address(farm));

        if (block.timestamp > pool.lastRewardBlock && lpSupply != 0) {
            uint multiplier = block.timestamp.sub(pool.lastRewardBlock);
            uint tokenReward = multiplier.mul(rewardPerBlock);
            accTokenPerShare = accTokenPerShare.add(tokenReward.mul(ACC_TOKEN_PRECISION).div(lpSupply));
        }

        return (user.amount.mul(accTokenPerShare).div(ACC_TOKEN_PRECISION)).sub(user.rewardDebt);
    } 
}