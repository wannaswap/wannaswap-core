// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/IRewarder.sol";

contract Rewarder is IRewarder {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    uint public immutable tokenPrecision;
    address public immutable wannaFarm;
    uint public rewardPerBlock; // actually per second
    uint public accRewardPerShare;
    mapping(address => uint) public rewardDebt;

    constructor(
        IERC20 _token,
        uint _rewardPerBlock,
        address _wannaFarm,
        uint _tokenPrecision
    ) public {
        token = _token;
        rewardPerBlock = _rewardPerBlock;
        wannaFarm = _wannaFarm;
        tokenPrecision = _tokenPrecision == 0 ? 1e18 : _tokenPrecision;
    }

    modifier onlyWannaFarm() {
        require(address(msg.sender) == wannaFarm, "Rewarder: MUST BE WANNAFARM");
        _;
    }

    function setRewardPerBlock(uint _rewardPerBlock, uint _blockCount, uint _lpSupply) external override onlyWannaFarm {
        update(_blockCount, _lpSupply);
        rewardPerBlock = _rewardPerBlock;
    }

    function update(uint _blockCount, uint _lpSupply) internal {
        uint reward = _blockCount.mul(rewardPerBlock);
        accRewardPerShare = accRewardPerShare.add(reward.mul(tokenPrecision).div(_lpSupply));
    }

    function onReward(address _user, uint _amount, uint _blockCount, uint _lpSupply) external override onlyWannaFarm {
        update(_blockCount, _lpSupply);

        uint pending = _amount.mul(accRewardPerShare).div(tokenPrecision).sub(rewardDebt[_user]);

        uint balance = token.balanceOf(address(this));

        if (pending > balance) {
            pending = balance;
        }

        rewardDebt[_user] = _amount.mul(accRewardPerShare).div(tokenPrecision);
        token.safeTransfer(_user, pending);
    }

    function pendingReward(address _user, uint _amount, uint _blockCount, uint _lpSupply) external override view returns (uint) {
        uint reward = _blockCount.mul(rewardPerBlock);
        uint tmpAccRewardPerShare = accRewardPerShare.add(reward.mul(tokenPrecision).div(_lpSupply));
        uint pending = _amount.mul(tmpAccRewardPerShare).div(tokenPrecision).sub(rewardDebt[_user]);

        uint balance = token.balanceOf(address(this));

        if (pending > balance) {
            pending = balance;
        }

        return pending;
    }
}