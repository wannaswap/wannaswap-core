// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/BoringMath.sol";
import "../interfaces/IRewarder.sol";
import "../interfaces/IWannaFarm.sol";
import "../interfaces/IWannaSwapProfile.sol";

contract WannaFarmV2 is Ownable, ReentrancyGuard {
    using BoringMath for uint;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint amount;
        uint rewardDebt;
    }

    struct PoolInfo {
        uint accWannaPerShare;
        uint lastRewardBlock;
        uint allocPoint;
        uint totalLp;
    }

    IWannaFarm public immutable WANNA_FARM;
    IERC20 public immutable WANNA;
    uint public immutable MASTER_PID;
    address public immutable dev;
    PoolInfo[] public poolInfo;
    IERC20[] public lpToken;
    IRewarder[] public rewarder;

    mapping(uint => mapping(address => UserInfo)) public userInfo;
    uint public totalAllocPoint;

    uint private constant ACC_WANNA_PRECISION = 1e18;

    event Deposit(address indexed user, uint indexed pid, uint amount, address ref);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event EmergencyWithdraw(
        address indexed user,
        uint indexed pid,
        uint amount
    );
    event Harvest(address indexed user, uint indexed pid, uint amount);
    event AddPool(
        uint indexed pid,
        uint allocPoint,
        IERC20 indexed lpToken,
        IRewarder indexed rewarder
    );
    event SetPool(
        uint indexed pid,
        uint allocPoint,
        IRewarder indexed rewarder,
        bool overwrite
    );
    event UpdatePool(
        uint indexed pid,
        uint lastRewardBlock,
        uint lpSupply,
        uint accWannaPerShare
    );
    event Init();

    constructor(
        IWannaFarm _WANNA_FARM,
        IERC20 _wanna,
        uint _MASTER_PID,
        address _dev
    ) public {
        WANNA_FARM = _WANNA_FARM;
        WANNA = _wanna;
        MASTER_PID = _MASTER_PID;
        dev = _dev;
    }

    function init(IERC20 _dummyToken) external {
        uint balance = _dummyToken.balanceOf(msg.sender);
        require(balance != 0, "WannaFarmV2: Balance must exceed 0");
        _dummyToken.safeTransferFrom(msg.sender, address(this), balance);
        _dummyToken.approve(address(WANNA_FARM), balance);
        // dev will get referral interest and send back to real users' referral
        WANNA_FARM.deposit(MASTER_PID, balance, dev);
        emit Init();
    }

    function poolLength() public view returns (uint pools) {
        pools = poolInfo.length;
    }

    function addPool(
        uint _allocPoint,
        IERC20 _lpToken,
        IRewarder _rewarder
    ) external onlyOwner {
        uint lastRewardBlock = block.timestamp;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        lpToken.push(_lpToken);
        rewarder.push(_rewarder);

        poolInfo.push(
            PoolInfo({
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accWannaPerShare: 0,
                totalLp: 0
            })
        );
        emit AddPool(lpToken.length.sub(1), _allocPoint, _lpToken, _rewarder);
    }

    function setPool(
        uint _pid,
        uint _allocPoint,
        IRewarder _rewarder,
        bool _overwrite
    ) external onlyOwner {
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
        if (_overwrite) {
            rewarder[_pid] = _rewarder;
        }
        emit SetPool(
            _pid,
            _allocPoint,
            _overwrite ? _rewarder : rewarder[_pid],
            _overwrite
        );
    }

    function pendingWanna(uint _pid, address _user)
        external
        view
        returns (uint pending)
    {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint accWannaPerShare = pool.accWannaPerShare;
        uint lpSupply = pool.totalLp;
        if (block.timestamp > pool.lastRewardBlock && lpSupply != 0) {
            uint blocks = block.timestamp.sub(pool.lastRewardBlock);
            uint wannaReward = blocks.mul(wannaPerBlock()).mul(
                pool.allocPoint
            ).div(totalAllocPoint);
            accWannaPerShare = accWannaPerShare.add(
                wannaReward.mul(ACC_WANNA_PRECISION).div(lpSupply)
            );
        }
        pending = user.amount.mul(accWannaPerShare).div(ACC_WANNA_PRECISION).sub(user.rewardDebt);
    }

    function pendingBonus(uint _pid, address _user)
        public
        view
        returns (uint pending)
    {
        if (address(rewarder[_pid]) != address(0)) pending = rewarder[_pid].pendingReward(_user);
    }

    function updateAllPools(uint[] calldata _pids) external {
        uint len = _pids.length;
        for (uint i = 0; i < len; ++i) {
            updatePool(_pids[i]);
        }
    }

    function wannaPerBlock() public view returns (uint amount) {
        amount =
            WANNA_FARM.wannaPerBlock().mul(
                WANNA_FARM.poolInfo(MASTER_PID).allocPoint
            ).div(WANNA_FARM.totalAllocPoint());
    }

    function updatePool(uint _pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[_pid];
        if (block.timestamp > pool.lastRewardBlock) {
            uint lpSupply = pool.totalLp;
            if (lpSupply > 0) {
                uint blocks = block.timestamp.sub(pool.lastRewardBlock);
                uint wannaReward = blocks.mul(wannaPerBlock()).mul(
                    pool.allocPoint
                ).div(totalAllocPoint);
                pool.accWannaPerShare = pool.accWannaPerShare.add(
                    (wannaReward.mul(ACC_WANNA_PRECISION).div(lpSupply))
                );
            }
            pool.lastRewardBlock = block.timestamp;
            poolInfo[_pid] = pool;
            emit UpdatePool(
                _pid,
                pool.lastRewardBlock,
                lpSupply,
                pool.accWannaPerShare
            );
        }
    }

    function deposit(
        uint _pid,
        uint _amount,
        address _ref
    ) external nonReentrant {
        harvestFromWannaFarm();
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint pending = user.amount.mul(pool.accWannaPerShare).div(ACC_WANNA_PRECISION).sub(user.rewardDebt);

        // Effects
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accWannaPerShare).div(ACC_WANNA_PRECISION);

        // Interactions
        WANNA.safeTransfer(msg.sender, pending);

        address profileAddress = WANNA_FARM.profile();
        if (profileAddress != address(0)) {
            IWannaSwapProfile profileContract = IWannaSwapProfile(
                profileAddress
            );

            if (WANNA_FARM.isEnableRef()) {
                uint refPending = pending.mul(WANNA_FARM.refPercent()).div(100e18); // referrer's reward = <refPercent> % referral's reward
                refPending = WANNA_FARM.calculate(refPending);

                if (refPending > 0) {
                    address referrer = profileContract.referrer(msg.sender);
                    if (referrer == address(0)) {
                        referrer = WANNA_FARM.burnAddress(); // if user does NOT have referrer => burn
                    }
                    profileContract.addEmission(msg.sender, refPending);
                    WANNA.safeTransferFrom(dev, referrer, refPending);
                }
            }

            if (_ref != address(0)) {
                profileContract.setReferrer(msg.sender, _ref);
            }
        }

        IRewarder _rewarder = rewarder[_pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(msg.sender, user.amount);
        }

        lpToken[_pid].safeTransferFrom(msg.sender, address(this), _amount);
        poolInfo[_pid].totalLp = poolInfo[_pid].totalLp.add(_amount);

        emit Deposit(msg.sender, _pid, _amount, _ref);
        emit Harvest(msg.sender, _pid, pending);
    }

    function withdraw(uint _pid, uint _amount) external nonReentrant {
        harvestFromWannaFarm();
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint pending = user.amount.mul(pool.accWannaPerShare).div(ACC_WANNA_PRECISION).sub(user.rewardDebt);

        // Effects
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accWannaPerShare).div(ACC_WANNA_PRECISION);

        // Interactions
        WANNA.safeTransfer(msg.sender, pending);

        IRewarder _rewarder = rewarder[_pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(msg.sender, user.amount);
        }

        lpToken[_pid].safeTransfer(msg.sender, _amount);
        poolInfo[_pid].totalLp = poolInfo[_pid].totalLp.sub(_amount);

        emit Withdraw(msg.sender, _pid, _amount);
        emit Harvest(msg.sender, _pid, pending);
    }

    function harvestFromWannaFarm() public {
        WANNA_FARM.deposit(MASTER_PID, 0, address(0));
    }

    function emergencyWithdraw(uint _pid) external nonReentrant {
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        // IRewarder _rewarder = rewarder[_pid];
        // if (address(_rewarder) != address(0)) {
        //     _rewarder.onReward(msg.sender, 0);
        // }

        // Note: transfer can fail or succeed if `amount` is zero.
        lpToken[_pid].safeTransfer(msg.sender, amount);
        poolInfo[_pid].totalLp = poolInfo[_pid].totalLp.sub(amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }
}
