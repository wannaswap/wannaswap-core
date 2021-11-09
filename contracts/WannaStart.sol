// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IWannaSwapPair.sol";

contract WannaStart is Ownable, ReentrancyGuard {
    string public name = "WannaStart";
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint lpAmount;
        uint savedMaxCommitment;
        uint commitment;
        uint claimedAmount;
        uint claimedRefundAmount;
        uint lastInteraction;
    }

    struct PoolInfo {
        address lpToken; // should be WETH, WNEAR, AURORA or WANNA
        address token; // offering token
        address mustHoldToken; // should be WANNA
        uint totalAmount;
        uint mustHoldAmount;
        uint totalLp; // amount of LP to raise included fee
        uint totalStakedLp;
        uint totalCommitment;
        uint totalUser;
        uint startTime;
        uint commitTime;
        uint endTime;
        uint claimTime;
    }

    uint public fee; // percent
    address public feeTo;

    PoolInfo[] public poolInfo;
    mapping (uint => mapping (address => UserInfo)) public userInfo;

    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event Commit(address indexed user, uint indexed pid, uint amount);
    event UnCommit(address indexed user, uint indexed pid, uint amount);
    event Claim(address indexed user, uint indexed pid, uint amount, uint refundAmount);
    event FinalizePool(address indexed user, uint indexed pid, address indexed fundTo, uint totalFee, uint amount);

    constructor(
        uint _fee,
        address _feeTo
    ) public {
        fee = _fee;
        feeTo = _feeTo;
    }

    function setFee(uint _fee) public onlyOwner {
        require(_fee < 100e18, "setFee: BAD FEE");
        fee = _fee;
    }

    function setFeeTo(address _feeTo) public onlyOwner {
        feeTo = _feeTo;
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    function addPool(address _lpToken, address _token, address _mustHoldToken, uint _totalAmount, uint _mustHoldAmount, uint _totalLp, uint _startTime, uint _commitTime, uint _endTime, uint _claimTime) public onlyOwner {
        require(_startTime > block.timestamp, "addPool: BAD STARTTIME");
        require(_commitTime > _startTime, "addPool: BAD COMMITTIME");
        require(_endTime > _commitTime, "addPool: BAD ENDTIME");
        require(_claimTime > _endTime, "addPool: BAD CLAIMTIME");
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            token: _token,
            mustHoldToken: _mustHoldToken,
            totalAmount: _totalAmount,
            mustHoldAmount: _mustHoldAmount,
            totalLp: _totalLp,
            totalStakedLp: 0,
            totalCommitment: 0,
            totalUser: 0,
            startTime: _startTime,
            commitTime: _commitTime,
            endTime: _endTime,
            claimTime: _claimTime
        }));
    }

    function setPool(uint _pid, address _lpToken, address _token, uint _totalAmount, uint _totalLp, uint _startTime, uint _commitTime, uint _endTime, uint _claimTime) public onlyOwner {
        require(_pid < poolInfo.length, "setPool: BAD POOL");
        require(_startTime > block.timestamp, "setPool: BAD STARTTIME");
        require(_commitTime > _startTime, "setPool: BAD COMMITTIME");
        require(_endTime > _commitTime, "setPool: BAD ENDTIME");
        require(_claimTime > _endTime, "setPool: BAD CLAIMTIME");
        
        poolInfo[_pid].lpToken = _lpToken;
        poolInfo[_pid].token = _token;
        poolInfo[_pid].totalAmount = _totalAmount;
        poolInfo[_pid].totalLp = _totalLp;
        poolInfo[_pid].startTime = _startTime;
        poolInfo[_pid].commitTime = _commitTime;
        poolInfo[_pid].endTime = _endTime;
        poolInfo[_pid].claimTime = _claimTime;
    }

    function maxCommitment(uint _pid, address _user) public view returns (uint) {
        require(_pid < poolInfo.length, "maxCommitment: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint savedMaxCommitment = user.savedMaxCommitment;
        if (block.timestamp > user.lastInteraction && user.lastInteraction > pool.startTime && pool.commitTime >= user.lastInteraction) {
            uint savedDuration = user.lastInteraction.sub(pool.startTime);
            uint pendingDuration = block.timestamp < pool.commitTime ? block.timestamp.sub(user.lastInteraction) : pool.commitTime.sub(user.lastInteraction);
            savedMaxCommitment = savedMaxCommitment.mul(savedDuration)
                                .add(user.lpAmount.mul(pendingDuration))
                                .div(savedDuration.add(pendingDuration));
        }
        return savedMaxCommitment;
    }

    function deposit(uint _pid, uint _amount) public nonReentrant {
        require(_pid < poolInfo.length, "deposit: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        require(block.timestamp >= pool.startTime, "deposit: NOT NOW");
        require(block.timestamp < pool.commitTime, "deposit: BAD TIME");
        UserInfo storage user = userInfo[_pid][msg.sender];

        user.savedMaxCommitment = maxCommitment(_pid, msg.sender);
        user.lastInteraction = block.timestamp;
        if(_amount > 0) {
            IERC20(pool.lpToken).safeTransferFrom(address(msg.sender), address(this), _amount);
            user.lpAmount = user.lpAmount.add(_amount);
            pool.totalStakedLp = pool.totalStakedLp.add(_amount);
        }
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint _pid, uint _amount) public nonReentrant {
        require(_pid < poolInfo.length, "withdraw: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        require(block.timestamp >= pool.startTime, "withdraw: NOT NOW");
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.lpAmount >= _amount, "withdraw: BAD AMOUNT");

        user.savedMaxCommitment = maxCommitment(_pid, msg.sender);
        user.lastInteraction = block.timestamp;
        if(_amount > 0) {
            user.lpAmount = user.lpAmount.sub(_amount);
            // started committing => save totalStakedLp to view
            if (block.timestamp >= pool.commitTime) {
                pool.totalStakedLp = pool.totalStakedLp.sub(_amount);
            }
            IERC20(pool.lpToken).safeTransfer(address(msg.sender), _amount);
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function commit(uint _pid, uint _amount) public nonReentrant {
        require(_pid < poolInfo.length, "commit: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        require(block.timestamp >= pool.commitTime, "commit: NOT NOW");
        require(block.timestamp < pool.endTime, "commit: BAD TIME");
        UserInfo storage user = userInfo[_pid][msg.sender];
        user.savedMaxCommitment = maxCommitment(_pid, msg.sender);
        require(user.savedMaxCommitment >= user.commitment.add(_amount), "commit: BAD AMOUNT");

        user.lastInteraction = block.timestamp;
        if(_amount > 0) {
            IERC20(pool.lpToken).safeTransferFrom(address(msg.sender), address(this), _amount);
            if (user.commitment == 0) {
                pool.totalUser = pool.totalUser.add(1);
            }
            user.commitment = user.commitment.add(_amount);
            pool.totalCommitment = pool.totalCommitment.add(_amount);
        }
        emit Commit(msg.sender, _pid, _amount);
    }

    function uncommit(uint _pid, uint _amount) public nonReentrant {
        require(_pid < poolInfo.length, "uncommit: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        require(block.timestamp >= pool.commitTime, "uncommit: NOT NOW");
        require(block.timestamp < pool.endTime, "uncommit: BAD TIME");
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.commitment >= _amount, "uncommit: BAD AMOUNT");

        user.lastInteraction = block.timestamp;
        if(_amount > 0) {
            user.commitment = user.commitment.sub(_amount);
            if (user.commitment == 0) {
                pool.totalUser = pool.totalUser.sub(1);
            }
            pool.totalCommitment = pool.totalCommitment.sub(_amount);
            IERC20(pool.lpToken).safeTransfer(address(msg.sender), _amount);
        }
        emit UnCommit(msg.sender, _pid, _amount);
    }

    function claimableAmount(uint _pid, address _user) public view returns (uint) {
        require(_pid < poolInfo.length, "claimableAmount: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        if (block.timestamp < pool.endTime) {
            return 0;
        }
        
        return user.commitment.mul(pool.totalAmount).div(pool.totalCommitment).sub(user.claimedAmount);
    }

    function claimableRefundAmount(uint _pid, address _user) public view returns (uint) {
        require(_pid < poolInfo.length, "claimableRefundAmount: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        if (block.timestamp < pool.endTime || pool.totalCommitment < pool.totalLp) {
            return 0;
        }
        
        return user.commitment.sub(user.commitment.mul(pool.totalLp).div(pool.totalCommitment)).sub(user.claimedRefundAmount);
    }

    function claim(uint _pid) public nonReentrant {
        require(_pid < poolInfo.length, "claim: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        require(block.timestamp >= pool.claimTime, "claim: NOT NOW");
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint pending = claimableAmount(_pid, msg.sender);
        uint pendingRefund = claimableRefundAmount(_pid, msg.sender);
        user.lastInteraction = block.timestamp;
        if(pending > 0) {
            uint balance = IERC20(pool.token).balanceOf(address(this));
            if (pending > balance) {
                pending = balance;
            }

            user.claimedAmount = user.claimedAmount.add(pending);
            IERC20(pool.token).safeTransfer(address(msg.sender), pending);
        }
        if(pendingRefund > 0) {
            uint balanceRefund = IERC20(pool.lpToken).balanceOf(address(this));
            if (pendingRefund > balanceRefund) {
                pendingRefund = balanceRefund;
            }

            user.claimedRefundAmount = user.claimedRefundAmount.add(pendingRefund);
            IERC20(pool.lpToken).safeTransfer(address(msg.sender), pendingRefund);
        }
        emit Claim(msg.sender, _pid, pending, pendingRefund);
    }

    function finalizePool(uint _pid, address _fundTo) public onlyOwner {
        require(_pid < poolInfo.length, "finalizePool: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        require(block.timestamp >= pool.claimTime, "finalizePool: NOT NOW");
        uint totalRaised = pool.totalCommitment > pool.totalLp ? pool.totalLp : pool.totalCommitment;
        uint balance = IERC20(pool.lpToken).balanceOf(address(this));
        if (totalRaised > balance) totalRaised = balance;
        uint totalFee = totalRaised.mul(fee).div(100e18);
        uint amount = totalRaised.sub(totalFee);
        // send fee to converter
        IERC20(pool.lpToken).safeTransfer(feeTo, totalFee);
        // send fund to offerer
        IERC20(pool.lpToken).safeTransfer(_fundTo, amount);
        emit FinalizePool(msg.sender, _pid, _fundTo, totalFee, amount);
    }
}