// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWannaFarm {
    struct UserInfo {
        uint amount;
        uint rewardDebt;
    }

    struct PoolInfo {
        IERC20 lpToken;
        uint allocPoint;
        uint lastRewardBlock;
        uint accWannaPerShare;
    }

    function poolInfo(uint _pid) external view returns (IWannaFarm.PoolInfo memory);
    function totalAllocPoint() external view returns (uint);
    function profile() external view returns (address);
    function burnAddress() external view returns (address);
    function refPercent() external view returns (uint);
    function isEnableRef() external view returns (bool);
    function calculate(uint _reward) external view returns (uint);
    function deposit(uint _pid, uint _amount, address _ref) external;
    function wannaPerBlock() external view returns (uint);    
    function pendingWanna(uint _pid, address _user) external view returns (uint);
}