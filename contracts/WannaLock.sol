// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract WannaLock {
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    
    struct Items {
        IERC20 token;
        address depositer;
        address withdrawer;
        uint amount;
        uint unlockTimestamp;
        bool withdrawn;
    }
    
    uint public depositsCount;
    mapping (address => uint[]) private depositsByTokenAddress;
    mapping (address => uint[]) public depositsByDepositer;
    mapping (address => uint[]) public depositsByWithdrawer;
    mapping (uint => Items) public lockedToken;
    mapping (address => mapping(address => uint)) public walletTokenBalance;
    
    event Withdraw(address withdrawer, uint amount);
    event Lock(address token, uint amount, uint id);
    
    function lockTokens(IERC20 _token, address _withdrawer, uint _amount, uint _unlockTimestamp) payable external returns (uint _id) {
        require(_amount > 0, 'Token amount too low!');
        require(_unlockTimestamp < 10000000000, 'Unlock timestamp is not in seconds!');
        require(_unlockTimestamp > block.timestamp, 'Unlock timestamp is not in the future!');
        require(_token.allowance(msg.sender, address(this)) >= _amount, 'Approve tokens first!');

        uint beforeDeposit = _token.balanceOf(address(this));
        _token.safeTransferFrom(msg.sender, address(this), _amount);
        uint afterDeposit = _token.balanceOf(address(this));
        
        _amount = afterDeposit.sub(beforeDeposit); 
                
        walletTokenBalance[address(_token)][msg.sender] = walletTokenBalance[address(_token)][msg.sender].add(_amount);
        
        _id = ++depositsCount;
        lockedToken[_id].token = _token;
        lockedToken[_id].depositer = msg.sender;
        lockedToken[_id].withdrawer = _withdrawer;
        lockedToken[_id].amount = _amount;
        lockedToken[_id].unlockTimestamp = _unlockTimestamp;
        lockedToken[_id].withdrawn = false;
        
        depositsByTokenAddress[address(_token)].push(_id);
        depositsByDepositer[msg.sender].push(_id);
        depositsByWithdrawer[_withdrawer].push(_id);

        emit Lock(address(_token), _amount, _id);
        
        return _id;
    }
        
    function withdrawTokens(uint _id) external {
        require(block.timestamp >= lockedToken[_id].unlockTimestamp, 'Tokens are still locked!');
        require(msg.sender == lockedToken[_id].withdrawer, 'You are not the withdrawer!');
        require(!lockedToken[_id].withdrawn, 'Tokens are already withdrawn!');
        
        lockedToken[_id].withdrawn = true;
        
        walletTokenBalance[address(lockedToken[_id].token)][lockedToken[_id].depositer] = walletTokenBalance[address(lockedToken[_id].token)][lockedToken[_id].depositer].sub(lockedToken[_id].amount);
        
        emit Withdraw(msg.sender, lockedToken[_id].amount);
        lockedToken[_id].token.safeTransfer(msg.sender, lockedToken[_id].amount);
    }
    
    function getDepositsByTokenAddress(address _token) view external returns (uint[] memory) {
        return depositsByTokenAddress[_token];
    }
    
    function getDepositsByDepositer(address _depositer) view external returns (uint[] memory) {
        return depositsByDepositer[_depositer];
    }
    
    function getDepositsByWithdrawer(address _withdrawer) view external returns (uint[] memory) {
        return depositsByWithdrawer[_withdrawer];
    }
    
    function getTokenTotalLockedBalance(address _token) view external returns (uint) {
       return IERC20(_token).balanceOf(address(this));
    }
}