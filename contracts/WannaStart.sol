// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract WannaStart is Ownable, ReentrancyGuard {
    string public name = "WannaStart";
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 lpAmount;
        uint256 savedMaxCommitment;
        uint256 commitment;
        uint256 claimedAmount;
        uint256 claimedRefundAmount;
        uint256 lastInteraction;
    }

    struct PoolInfo {
        address lpToken; // should be wLP Token, wNEAR, AURORA or WANNA, not supports deflationary tokens or tokens with rebase
        address token; // offering token
        address mustHoldToken; // should be WANNA
        uint256 totalAmount;
        uint256 mustHoldAmount;
        uint256 totalLp; // amount of LP to raise included fee
        uint256 totalStakedLp;
        uint256 totalCommitment;
        uint256 totalUser;
        uint256 startTime;
        uint256 commitTime;
        uint256 endTime;
        uint256 claimTime;
    }

    uint256 public fee; // percent
    address public feeTo;

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(uint256 => bool) public isFinalized;

    event SetFee(uint256 fee);
    event SetFeeTo(address feeTo);
    event AddPool(
        address lpToken,
        address token,
        address mustHoldToken,
        uint256 totalAmount,
        uint256 mustHoldAmount,
        uint256 totalLp,
        uint256 startTime,
        uint256 commitTime,
        uint256 endTime,
        uint256 claimTime
    );
    event SetPool(
        uint256 indexed pid,
        address lpToken,
        address token,
        uint256 totalAmount,
        uint256 totalLp,
        uint256 startTime,
        uint256 commitTime,
        uint256 endTime,
        uint256 claimTime
    );
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Commit(address indexed user, uint256 indexed pid, uint256 amount);
    event UnCommit(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        uint256 refundAmount
    );
    event FinalizePool(
        address indexed user,
        uint256 indexed pid,
        address indexed fundTo,
        uint256 totalFee,
        uint256 amount
    );

    constructor(uint256 _fee, address _feeTo) public {
        fee = _fee;
        feeTo = _feeTo;
    }

    function setFee(uint256 _fee) external onlyOwner {
        require(_fee < 100e18, "setFee: BAD FEE");
        fee = _fee;

        emit SetFee(_fee);
    }

    function setFeeTo(address _feeTo) external onlyOwner {
        require(_feeTo != address(0), "setFeeTo: BAD ADDRESS");
        feeTo = _feeTo;

        emit SetFeeTo(_feeTo);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function addPool(
        address _lpToken,
        address _token,
        address _mustHoldToken,
        uint256 _totalAmount,
        uint256 _mustHoldAmount,
        uint256 _totalLp,
        uint256 _startTime,
        uint256 _commitTime,
        uint256 _endTime,
        uint256 _claimTime
    ) external onlyOwner {
        require(_startTime > block.timestamp, "addPool: BAD STARTTIME");
        require(_commitTime > _startTime, "addPool: BAD COMMITTIME");
        require(_endTime > _commitTime, "addPool: BAD ENDTIME");
        require(_claimTime > _endTime, "addPool: BAD CLAIMTIME");
        poolInfo.push(
            PoolInfo({
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
            })
        );

        emit AddPool(
            _lpToken,
            _token,
            _mustHoldToken,
            _totalAmount,
            _mustHoldAmount,
            _totalLp,
            _startTime,
            _commitTime,
            _endTime,
            _claimTime
        );
    }

    function setPool(
        uint256 _pid,
        address _lpToken,
        address _token,
        address _mustHoldToken,
        uint256 _totalAmount,
        uint256 _mustHoldAmount,
        uint256 _totalLp,
        uint256 _startTime,
        uint256 _commitTime,
        uint256 _endTime,
        uint256 _claimTime
    ) external onlyOwner {
        require(_pid < poolInfo.length, "setPool: BAD POOL");
        require(
            poolInfo[_pid].startTime > block.timestamp,
            "setPool: RESTRICTED"
        );
        require(_startTime > block.timestamp, "setPool: BAD STARTTIME");
        require(_commitTime > _startTime, "setPool: BAD COMMITTIME");
        require(_endTime > _commitTime, "setPool: BAD ENDTIME");
        require(_claimTime > _endTime, "setPool: BAD CLAIMTIME");

        poolInfo[_pid].lpToken = _lpToken;
        poolInfo[_pid].token = _token;
        poolInfo[_pid].mustHoldToken = _mustHoldToken;
        poolInfo[_pid].totalAmount = _totalAmount;
        poolInfo[_pid].mustHoldAmount = _mustHoldAmount;
        poolInfo[_pid].totalLp = _totalLp;
        poolInfo[_pid].startTime = _startTime;
        poolInfo[_pid].commitTime = _commitTime;
        poolInfo[_pid].endTime = _endTime;
        poolInfo[_pid].claimTime = _claimTime;

        emit SetPool(
            _pid,
            _lpToken,
            _token,
            _totalAmount,
            _totalLp,
            _startTime,
            _commitTime,
            _endTime,
            _claimTime
        );
    }

    function maxCommitment(uint256 _pid, address _user)
        public
        view
        returns (uint256)
    {
        if (_pid >= poolInfo.length) {
            return 0;
        }
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 savedMaxCommitment = user.savedMaxCommitment;
        uint256 lastInteraction = user.lastInteraction;
        uint256 startTime = pool.startTime;
        uint256 commitTime = pool.commitTime;
        if (
            block.timestamp > lastInteraction &&
            lastInteraction > startTime &&
            commitTime >= lastInteraction
        ) {
            uint256 savedDuration = lastInteraction.sub(startTime);
            uint256 pendingDuration = block.timestamp < commitTime
                ? block.timestamp.sub(lastInteraction)
                : commitTime.sub(lastInteraction);
            savedMaxCommitment = savedMaxCommitment
                .mul(savedDuration)
                .add(user.lpAmount.mul(pendingDuration))
                .div(savedDuration.add(pendingDuration));
        }
        return savedMaxCommitment;
    }

    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        require(_pid < poolInfo.length, "deposit: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        require(block.timestamp >= pool.startTime, "deposit: NOT NOW");
        require(block.timestamp < pool.commitTime, "deposit: BAD TIME");
        address mustHoldToken = pool.mustHoldToken;
        if (mustHoldToken != address(0)) {
            require(
                IERC20(mustHoldToken).balanceOf(msg.sender) >=
                    pool.mustHoldAmount,
                "deposit: Must hold enough required tokens"
            );
        }
        UserInfo storage user = userInfo[_pid][msg.sender];

        user.savedMaxCommitment = maxCommitment(_pid, msg.sender);
        user.lastInteraction = block.timestamp;
        if (_amount > 0) {
            IERC20(pool.lpToken).safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.lpAmount = user.lpAmount.add(_amount);
            pool.totalStakedLp = pool.totalStakedLp.add(_amount);
        }
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        require(_pid < poolInfo.length, "withdraw: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        require(block.timestamp >= pool.startTime, "withdraw: NOT NOW");
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.lpAmount >= _amount, "withdraw: BAD AMOUNT");

        user.savedMaxCommitment = maxCommitment(_pid, msg.sender);
        user.lastInteraction = block.timestamp;
        if (_amount > 0) {
            user.lpAmount = user.lpAmount.sub(_amount);
            // started committing => save totalStakedLp to view
            if (block.timestamp < pool.commitTime) {
                pool.totalStakedLp = pool.totalStakedLp.sub(_amount);
            }
            IERC20(pool.lpToken).safeTransfer(address(msg.sender), _amount);
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function commit(uint256 _pid, uint256 _amount) external nonReentrant {
        require(_pid < poolInfo.length, "commit: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        require(block.timestamp >= pool.commitTime, "commit: NOT NOW");
        require(block.timestamp < pool.endTime, "commit: BAD TIME");
        address mustHoldToken = pool.mustHoldToken;
        if (mustHoldToken != address(0)) {
            require(
                IERC20(mustHoldToken).balanceOf(msg.sender) >=
                    pool.mustHoldAmount,
                "deposit: Must hold enough required tokens"
            );
        }
        UserInfo storage user = userInfo[_pid][msg.sender];
        user.savedMaxCommitment = maxCommitment(_pid, msg.sender);
        uint256 commitment = user.commitment;
        require(
            user.savedMaxCommitment >= commitment.add(_amount),
            "commit: BAD AMOUNT"
        );

        user.lastInteraction = block.timestamp;
        if (_amount > 0) {
            IERC20(pool.lpToken).safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            if (commitment == 0) {
                pool.totalUser = pool.totalUser.add(1);
            }
            user.commitment = commitment.add(_amount);
            pool.totalCommitment = pool.totalCommitment.add(_amount);
        }
        emit Commit(msg.sender, _pid, _amount);
    }

    function uncommit(uint256 _pid, uint256 _amount) external nonReentrant {
        require(_pid < poolInfo.length, "uncommit: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        require(block.timestamp >= pool.commitTime, "uncommit: NOT NOW");
        require(block.timestamp < pool.endTime, "uncommit: BAD TIME");
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 commitment = user.commitment;
        require(commitment >= _amount, "uncommit: BAD AMOUNT");

        user.lastInteraction = block.timestamp;
        if (_amount > 0) {
            user.commitment = commitment.sub(_amount);
            if (user.commitment == 0) {
                pool.totalUser = pool.totalUser.sub(1);
            }
            pool.totalCommitment = pool.totalCommitment.sub(_amount);
            IERC20(pool.lpToken).safeTransfer(address(msg.sender), _amount);
        }
        emit UnCommit(msg.sender, _pid, _amount);
    }

    function claimableAmount(uint256 _pid, address _user)
        public
        view
        returns (uint256)
    {
        require(_pid < poolInfo.length, "claimableAmount: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        if (block.timestamp < pool.endTime) {
            return 0;
        }

        return
            user.commitment.mul(pool.totalAmount).div(pool.totalCommitment).sub(
                user.claimedAmount
            );
    }

    function claimableRefundAmount(uint256 _pid, address _user)
        public
        view
        returns (uint256)
    {
        require(_pid < poolInfo.length, "claimableRefundAmount: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 totalCommitment = pool.totalCommitment;
        uint256 totalLp = pool.totalLp;
        if (block.timestamp < pool.endTime || totalCommitment < totalLp) {
            return 0;
        }
        uint256 commitment = user.commitment;

        return
            commitment.sub(commitment.mul(totalLp).div(totalCommitment)).sub(
                user.claimedRefundAmount
            );
    }

    function claim(uint256 _pid) external nonReentrant {
        require(_pid < poolInfo.length, "claim: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        require(block.timestamp >= pool.claimTime, "claim: NOT NOW");
        address mustHoldToken = pool.mustHoldToken;
        if (mustHoldToken != address(0)) {
            require(
                IERC20(mustHoldToken).balanceOf(msg.sender) >=
                    pool.mustHoldAmount,
                "deposit: Must hold enough required tokens"
            );
        }
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 pending = claimableAmount(_pid, msg.sender);
        uint256 pendingRefund = claimableRefundAmount(_pid, msg.sender);
        user.lastInteraction = block.timestamp;
        IERC20 token = IERC20(pool.token);
        if (pending > 0) {
            uint256 balance = token.balanceOf(address(this));
            if (pending > balance) {
                pending = balance;
            }

            user.claimedAmount = user.claimedAmount.add(pending);
            token.safeTransfer(address(msg.sender), pending);
        }
        if (pendingRefund > 0) {
            IERC20 lp = IERC20(pool.lpToken);
            uint256 balanceRefund = lp.balanceOf(address(this));
            if (pendingRefund > balanceRefund) {
                pendingRefund = balanceRefund;
            }

            user.claimedRefundAmount = user.claimedRefundAmount.add(
                pendingRefund
            );
            lp.safeTransfer(address(msg.sender), pendingRefund);
        }
        emit Claim(msg.sender, _pid, pending, pendingRefund);
    }

    function finalizePool(uint256 _pid, address _fundTo) external onlyOwner {
        require(_pid < poolInfo.length, "finalizePool: BAD POOL");
        PoolInfo storage pool = poolInfo[_pid];
        require(!isFinalized[_pid], "finalizePool: ALREADY FINALIZED");
        require(block.timestamp >= pool.claimTime, "finalizePool: NOT NOW");
        uint256 totalCommitment = pool.totalCommitment;
        uint256 totalLp = pool.totalLp;
        IERC20 lpToken = IERC20(pool.lpToken);
        uint256 totalRaised = totalCommitment > totalLp
            ? totalLp
            : totalCommitment;
        uint256 balance = lpToken.balanceOf(address(this));
        if (totalRaised > balance) totalRaised = balance;
        uint256 totalFee = totalRaised.mul(fee).div(100e18);
        uint256 amount = totalRaised.sub(totalFee);
        // send fee to converter
        lpToken.safeTransfer(feeTo, totalFee);
        // send fund to offerer
        lpToken.safeTransfer(_fundTo, amount);
        isFinalized[_pid] = true;
        emit FinalizePool(msg.sender, _pid, _fundTo, totalFee, amount);
    }
}
